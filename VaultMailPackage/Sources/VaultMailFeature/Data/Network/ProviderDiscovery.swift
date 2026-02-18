import Foundation

/// Protocol for network requests, enabling test injection.
public protocol URLSessionProviding: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProviding {}

/// Auto-discovers IMAP/SMTP configuration for an email domain.
///
/// Implements a 4-tier discovery chain (FR-MPROV-08):
/// 1. **Static registry** — instant O(1) lookup for known providers
/// 2. **Mozilla ISPDB** — Thunderbird autoconfig database (XML)
/// 3. **DNS SRV / MX** — standard service discovery records
/// 4. **Manual fallback** — returns nil, caller shows manual setup
///
/// Results are cached for 30 days per domain (OQ-04).
/// Each tier has a 10-second timeout; total discovery timeout is 30 seconds.
///
/// Spec ref: FR-MPROV-08
public actor ProviderDiscovery {

    // MARK: - Cache

    private struct CacheEntry: Sendable {
        let config: DiscoveredConfig
        let cachedAt: Date
        /// Tracks last access time for LRU eviction.
        var lastAccessedAt: Date
    }

    /// Cache TTL: 30 days
    private static let cacheTTL: TimeInterval = 30 * 24 * 60 * 60

    /// Maximum cache entries before LRU eviction kicks in.
    private static let maxCacheSize = 100

    /// Per-tier timeout: 10 seconds
    private static let tierTimeout: TimeInterval = 10

    private var cache: [String: CacheEntry] = [:]
    private let urlSession: URLSessionProviding

    // MARK: - Init

    public init(urlSession: URLSessionProviding = URLSession.shared) {
        self.urlSession = urlSession
    }

    // MARK: - Public API

    /// Discovers IMAP/SMTP configuration for the given email address.
    ///
    /// Attempts discovery in order: static registry → ISPDB → DNS → nil.
    /// Returns the first successful result. Cached results are returned
    /// immediately for 30 days.
    ///
    /// - Parameter email: Full email address (e.g., "user@example.com")
    /// - Returns: Discovered configuration, or `nil` if all tiers fail.
    public func discover(for email: String) async -> DiscoveredConfig? {
        guard let domain = extractDomain(from: email) else { return nil }

        // Check cache first
        if var cached = cache[domain], Date().timeIntervalSince(cached.cachedAt) < Self.cacheTTL {
            cached.lastAccessedAt = Date()
            cache[domain] = cached
            return cached.config
        }

        // Tier 1: Static registry (instant)
        if let config = discoverFromRegistry(email: email) {
            cacheResult(config, for: domain)
            return config
        }

        // Tier 2: Mozilla ISPDB (network)
        if let config = await discoverFromISPDB(domain: domain) {
            cacheResult(config, for: domain)
            return config
        }

        // Tier 3: DNS SRV / MX (network)
        if let config = await discoverFromDNS(domain: domain) {
            cacheResult(config, for: domain)
            return config
        }

        // Tier 4: Manual fallback — return nil
        return nil
    }

    /// Clears the discovery cache for a specific domain or all domains.
    public func clearCache(for domain: String? = nil) {
        if let domain {
            cache.removeValue(forKey: domain.lowercased())
        } else {
            cache.removeAll()
        }
    }

    // MARK: - Tier 1: Static Registry

    private func discoverFromRegistry(email: String) -> DiscoveredConfig? {
        guard let config = ProviderRegistry.provider(for: email) else { return nil }
        return config.toDiscoveredConfig()
    }

    // MARK: - Tier 2: Mozilla ISPDB

    /// Queries Mozilla's ISPDB for autoconfig XML.
    ///
    /// URL format: `https://autoconfig.thunderbird.net/v1.1/{domain}`
    /// The response is XML with `<incomingServer>` and `<outgoingServer>` elements.
    private func discoverFromISPDB(domain: String) async -> DiscoveredConfig? {
        // Validate domain to prevent path traversal (P1-02)
        let validDomain = domain.lowercased()
        guard !validDomain.isEmpty,
              validDomain.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }),
              let encoded = validDomain.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        let urlString = "https://autoconfig.thunderbird.net/v1.1/\(encoded)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await withTimeout(seconds: Self.tierTimeout) {
                try await self.urlSession.data(from: url)
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            return parseISPDBResponse(data)
        } catch {
            NSLog("[Discovery] ISPDB lookup failed for \(domain): \(error.localizedDescription)")
            return nil
        }
    }

    /// Parses Mozilla ISPDB autoconfig XML.
    ///
    /// Extracts the first `<incomingServer type="imap">` and `<outgoingServer type="smtp">`.
    internal func parseISPDBResponse(_ data: Data) -> DiscoveredConfig? {
        let parser = ISPDBXMLParser(data: data)
        guard parser.parse(),
              let incoming = parser.incomingServer,
              let outgoing = parser.outgoingServer else {
            return nil
        }

        let imapSecurity = Self.mapSocketType(incoming.socketType)
        let smtpSecurity = Self.mapSocketType(outgoing.socketType)

        // Determine auth method from ISPDB XML <authentication> element.
        // Use the incoming (IMAP) server's auth as the primary signal.
        let authMethod = Self.mapAuthentication(incoming.authentication)

        return DiscoveredConfig(
            imapHost: incoming.hostname,
            imapPort: incoming.port,
            imapSecurity: imapSecurity,
            smtpHost: outgoing.hostname,
            smtpPort: outgoing.port,
            smtpSecurity: smtpSecurity,
            authMethod: authMethod,
            source: .ispdb,
            displayName: parser.displayName
        )
    }

    private static func mapSocketType(_ socketType: String) -> ConnectionSecurity {
        switch socketType.uppercased() {
        case "SSL", "TLS": return .tls
        case "STARTTLS": return .starttls
        default: return .tls
        }
    }

    /// Maps an ISPDB `<authentication>` value to `AuthMethod`.
    ///
    /// Mozilla ISPDB uses values like "OAuth2", "password-cleartext",
    /// "password-encrypted", etc. We map OAuth variants to `.xoauth2`
    /// and everything else to `.plain` (safe default for app-password flows).
    ///
    /// Spec ref: FR-MPROV-08 (ISPDB auth parsing)
    internal static func mapAuthentication(_ authentication: String?) -> AuthMethod {
        switch authentication?.lowercased() {
        case "oauth2", "xoauth2":
            return .xoauth2
        case "password-cleartext", "plain", "password-encrypted", "cram-md5", .none:
            return .plain
        default:
            return .plain
        }
    }

    // MARK: - Tier 3: DNS SRV / MX Heuristic

    /// Attempts to discover configuration via DNS MX records.
    ///
    /// Resolves MX records for the domain and maps well-known mail exchangers
    /// to provider configs. For example, if MX points to `*.google.com`,
    /// we know it's Google Workspace using Gmail infrastructure.
    private func discoverFromDNS(domain: String) async -> DiscoveredConfig? {
        do {
            let mxHosts = try await withTimeout(seconds: Self.tierTimeout) {
                try await self.resolveMXRecords(for: domain)
            }

            // Try to match MX host to a known provider
            for mx in mxHosts {
                let mxLower = mx.lowercased()

                if mxLower.hasSuffix(".google.com") || mxLower.hasSuffix(".googlemail.com") {
                    return ProviderRegistry.gmail.toDiscoveredConfig()
                }
                if mxLower.hasSuffix(".outlook.com") || mxLower.hasSuffix(".microsoft.com") {
                    return ProviderRegistry.outlook.toDiscoveredConfig()
                }
                if mxLower.hasSuffix(".yahoodns.net") || mxLower.contains("yahoo.com") {
                    return ProviderRegistry.yahoo.toDiscoveredConfig()
                }
                if mxLower.hasSuffix(".icloud.com") || mxLower.hasSuffix(".me.com") {
                    return ProviderRegistry.icloud.toDiscoveredConfig()
                }
            }

            // MX found but not a known provider — use domain-based heuristic
            if !mxHosts.isEmpty {
                return DiscoveredConfig(
                    imapHost: "imap.\(domain)",
                    imapPort: 993,
                    imapSecurity: .tls,
                    smtpHost: "smtp.\(domain)",
                    smtpPort: 587,
                    smtpSecurity: .starttls,
                    authMethod: .plain,
                    source: .dns,
                    displayName: nil
                )
            }

            return nil
        } catch {
            NSLog("[Discovery] DNS lookup failed for \(domain): \(error.localizedDescription)")
            return nil
        }
    }

    /// Resolves MX records for a domain using the `/usr/bin/host` command.
    ///
    /// **iOS limitation**: This method uses `Process` (Foundation), which is only
    /// available on macOS. On iOS, `Process` is not part of the public API and
    /// will not compile. The `#if os(macOS)` guard ensures that iOS builds
    /// return an empty array, effectively disabling Tier 3 DNS discovery.
    /// On iOS, provider discovery relies on Tier 1 (static registry) and
    /// Tier 2 (Mozilla ISPDB). If both fail, the user is shown the manual
    /// setup screen (Tier 4 fallback).
    ///
    /// A future improvement could use `dnssd` (DNS Service Discovery) framework
    /// or `CFHost` for cross-platform MX resolution.
    ///
    /// Falls back to an empty array on failure.
    private func resolveMXRecords(for domain: String) async throws -> [String] {
        #if os(macOS)
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/host")
                process.arguments = ["-t", "mx", domain]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    // Parse "domain mail is handled by 10 mx.example.com."
                    let mxHosts = output
                        .components(separatedBy: "\n")
                        .compactMap { line -> String? in
                            guard line.contains("mail is handled by") else { return nil }
                            let parts = line.components(separatedBy: " ")
                            guard let last = parts.last, !last.isEmpty else { return nil }
                            // Remove trailing dot
                            return last.hasSuffix(".") ? String(last.dropLast()) : last
                        }

                    continuation.resume(returning: mxHosts)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
        #else
        return []
        #endif
    }

    // MARK: - Helpers

    private func extractDomain(from email: String) -> String? {
        guard let atIndex = email.lastIndex(of: "@") else { return nil }
        let domain = String(email[email.index(after: atIndex)...]).lowercased()
        return domain.isEmpty ? nil : domain
    }

    private func cacheResult(_ config: DiscoveredConfig, for domain: String) {
        let now = Date()
        cache[domain] = CacheEntry(config: config, cachedAt: now, lastAccessedAt: now)

        // LRU eviction: if cache exceeds max size, remove the least recently accessed entry.
        if cache.count > Self.maxCacheSize {
            if let lruKey = cache.min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })?.key {
                cache.removeValue(forKey: lruKey)
            }
        }
    }

    /// Runs an async operation with a timeout.
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }

            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }
}

// MARK: - ISPDB XML Parser

/// Parses Mozilla ISPDB autoconfig XML format.
///
/// Extracts the first `<incomingServer type="imap">` and `<outgoingServer type="smtp">`
/// elements with their hostname, port, and socketType.
///
/// This class is only used synchronously within the `ProviderDiscovery` actor,
/// so it does not need `Sendable` conformance.
final class ISPDBXMLParser: NSObject, XMLParserDelegate {

    struct ServerConfig {
        var hostname: String = ""
        var port: Int = 0
        var socketType: String = ""
        /// Raw `<authentication>` value from ISPDB XML (e.g., "OAuth2", "password-cleartext").
        var authentication: String?
    }

    private let data: Data
    private let parser: XMLParser

    var displayName: String?
    var incomingServer: ServerConfig?
    var outgoingServer: ServerConfig?

    // Parser state
    private var currentElement = ""
    private var currentText = ""
    private var parsingIncoming = false
    private var parsingOutgoing = false
    private var parsingDisplayName = false
    private var currentServer = ServerConfig()

    init(data: Data) {
        self.data = data
        self.parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parse() -> Bool {
        parser.parse()
        return incomingServer != nil && outgoingServer != nil
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        currentElement = elementName
        currentText = ""

        if elementName == "incomingServer" && attributeDict["type"] == "imap" && incomingServer == nil {
            parsingIncoming = true
            currentServer = ServerConfig()
        } else if elementName == "outgoingServer" && attributeDict["type"] == "smtp" && outgoingServer == nil {
            parsingOutgoing = true
            currentServer = ServerConfig()
        } else if elementName == "displayName" {
            parsingDisplayName = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if parsingIncoming || parsingOutgoing {
            switch elementName {
            case "hostname":
                currentServer.hostname = trimmed
            case "port":
                currentServer.port = Int(trimmed) ?? 0
            case "socketType":
                currentServer.socketType = trimmed
            case "authentication":
                currentServer.authentication = trimmed
            default:
                break
            }
        }

        if elementName == "incomingServer" && parsingIncoming {
            parsingIncoming = false
            if !currentServer.hostname.isEmpty && currentServer.port > 0 {
                incomingServer = currentServer
            }
        } else if elementName == "outgoingServer" && parsingOutgoing {
            parsingOutgoing = false
            if !currentServer.hostname.isEmpty && currentServer.port > 0 {
                outgoingServer = currentServer
            }
        } else if elementName == "displayName" && parsingDisplayName {
            parsingDisplayName = false
            if displayName == nil && !trimmed.isEmpty {
                displayName = trimmed
            }
        }

        currentText = ""
    }
}
