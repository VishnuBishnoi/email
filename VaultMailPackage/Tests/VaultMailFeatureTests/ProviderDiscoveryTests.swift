import Foundation
import Testing
@testable import VaultMailFeature

@Suite("ProviderDiscovery Tests")
struct ProviderDiscoveryTests {

    // MARK: - Mock URL Session

    /// Mock URL session that returns predefined responses for specific URLs.
    final class MockURLSession: URLSessionProviding, @unchecked Sendable {
        var responses: [String: (Data, URLResponse)] = [:]
        var requestedURLs: [URL] = []
        var shouldThrow = false

        func data(from url: URL) async throws -> (Data, URLResponse) {
            requestedURLs.append(url)
            if shouldThrow {
                throw URLError(.notConnectedToInternet)
            }
            if let response = responses[url.absoluteString] {
                return response
            }
            let httpResponse = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (Data(), httpResponse)
        }
    }

    // MARK: - ISPDB XML Fixtures

    private static let fastmailISPDBXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <clientConfig version="1.1">
      <emailProvider id="fastmail.com">
        <domain>fastmail.com</domain>
        <displayName>Fastmail</displayName>
        <incomingServer type="imap">
          <hostname>imap.fastmail.com</hostname>
          <port>993</port>
          <socketType>SSL</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILADDRESS%</username>
        </incomingServer>
        <outgoingServer type="smtp">
          <hostname>smtp.fastmail.com</hostname>
          <port>465</port>
          <socketType>SSL</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILADDRESS%</username>
        </outgoingServer>
      </emailProvider>
    </clientConfig>
    """

    private static let starttlsISPDBXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <clientConfig version="1.1">
      <emailProvider id="example.org">
        <domain>example.org</domain>
        <displayName>Example Mail</displayName>
        <incomingServer type="imap">
          <hostname>mail.example.org</hostname>
          <port>143</port>
          <socketType>STARTTLS</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILADDRESS%</username>
        </incomingServer>
        <outgoingServer type="smtp">
          <hostname>smtp.example.org</hostname>
          <port>587</port>
          <socketType>STARTTLS</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILADDRESS%</username>
        </outgoingServer>
      </emailProvider>
    </clientConfig>
    """

    private static let oauth2ISPDBXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <clientConfig version="1.1">
      <emailProvider id="gmail.com">
        <domain>gmail.com</domain>
        <displayName>Google Mail</displayName>
        <incomingServer type="imap">
          <hostname>imap.gmail.com</hostname>
          <port>993</port>
          <socketType>SSL</socketType>
          <authentication>OAuth2</authentication>
          <username>%EMAILADDRESS%</username>
        </incomingServer>
        <outgoingServer type="smtp">
          <hostname>smtp.gmail.com</hostname>
          <port>465</port>
          <socketType>SSL</socketType>
          <authentication>OAuth2</authentication>
          <username>%EMAILADDRESS%</username>
        </outgoingServer>
      </emailProvider>
    </clientConfig>
    """

    private static let incompleteISPDBXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <clientConfig version="1.1">
      <emailProvider id="broken.com">
        <domain>broken.com</domain>
        <incomingServer type="pop3">
          <hostname>pop.broken.com</hostname>
          <port>995</port>
          <socketType>SSL</socketType>
        </incomingServer>
      </emailProvider>
    </clientConfig>
    """

    // MARK: - Tier 1: Static Registry

    @Test("Discover returns static registry for known Gmail domain")
    func discoverGmail() async {
        let session = MockURLSession()
        let sut = ProviderDiscovery(urlSession: session)

        let result = await sut.discover(for: "user@gmail.com")

        #expect(result != nil)
        #expect(result?.source == .staticRegistry)
        #expect(result?.imapHost == "imap.gmail.com")
        #expect(result?.imapPort == 993)
        #expect(result?.smtpHost == "smtp.gmail.com")
        #expect(result?.authMethod == .xoauth2)
        #expect(result?.displayName == "Gmail")
        // Should not have made any network requests
        #expect(session.requestedURLs.isEmpty)
    }

    @Test("Discover returns static registry for iCloud domain")
    func discoverICloud() async {
        let session = MockURLSession()
        let sut = ProviderDiscovery(urlSession: session)

        let result = await sut.discover(for: "user@icloud.com")

        #expect(result?.source == .staticRegistry)
        #expect(result?.imapHost == "imap.mail.me.com")
        #expect(result?.smtpSecurity == .starttls)
        #expect(result?.authMethod == .plain)
    }

    @Test("Discover returns static registry for Yahoo alternate domain")
    func discoverYahoo() async {
        let session = MockURLSession()
        let sut = ProviderDiscovery(urlSession: session)

        let result = await sut.discover(for: "user@ymail.com")

        #expect(result?.source == .staticRegistry)
        #expect(result?.imapHost == "imap.mail.yahoo.com")
        #expect(result?.authMethod == .plain)
    }

    // MARK: - Tier 2: ISPDB

    @Test("Discover uses ISPDB for unknown domain with SSL config")
    func discoverISPDB_SSL() async {
        let session = MockURLSession()
        let url = "https://autoconfig.thunderbird.net/v1.1/fastmail.com"
        let httpResponse = HTTPURLResponse(
            url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        session.responses[url] = (Self.fastmailISPDBXML.data(using: .utf8)!, httpResponse)

        let sut = ProviderDiscovery(urlSession: session)

        let result = await sut.discover(for: "user@fastmail.com")

        #expect(result != nil)
        #expect(result?.source == .ispdb)
        #expect(result?.imapHost == "imap.fastmail.com")
        #expect(result?.imapPort == 993)
        #expect(result?.imapSecurity == .tls)
        #expect(result?.smtpHost == "smtp.fastmail.com")
        #expect(result?.smtpPort == 465)
        #expect(result?.smtpSecurity == .tls)
        #expect(result?.displayName == "Fastmail")
        #expect(result?.authMethod == .plain)
    }

    @Test("Discover uses ISPDB with STARTTLS config")
    func discoverISPDB_STARTTLS() async {
        let session = MockURLSession()
        let url = "https://autoconfig.thunderbird.net/v1.1/example.org"
        let httpResponse = HTTPURLResponse(
            url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        session.responses[url] = (Self.starttlsISPDBXML.data(using: .utf8)!, httpResponse)

        let sut = ProviderDiscovery(urlSession: session)

        let result = await sut.discover(for: "user@example.org")

        #expect(result?.source == .ispdb)
        #expect(result?.imapHost == "mail.example.org")
        #expect(result?.imapPort == 143)
        #expect(result?.imapSecurity == .starttls)
        #expect(result?.smtpHost == "smtp.example.org")
        #expect(result?.smtpPort == 587)
        #expect(result?.smtpSecurity == .starttls)
        #expect(result?.displayName == "Example Mail")
    }

    @Test("ISPDB skips incomplete XML and falls through to DNS tier")
    func discoverISPDB_Incomplete() async {
        let session = MockURLSession()
        // Use .test TLD which won't have real MX records
        let url = "https://autoconfig.thunderbird.net/v1.1/broken-no-imap.test"
        let httpResponse = HTTPURLResponse(
            url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        session.responses[url] = (Self.incompleteISPDBXML.data(using: .utf8)!, httpResponse)

        let sut = ProviderDiscovery(urlSession: session)

        let result = await sut.discover(for: "user@broken-no-imap.test")

        // ISPDB has no IMAP server (only POP3), so it falls through.
        // .test TLD won't have MX records, so DNS tier also returns nil.
        #expect(result == nil)
    }

    @Test("ISPDB returns nil on network failure")
    func discoverISPDB_NetworkFailure() async {
        let session = MockURLSession()
        session.shouldThrow = true

        let sut = ProviderDiscovery(urlSession: session)

        let result = await sut.discover(for: "user@unknown-domain.test")

        #expect(result == nil)
    }

    // MARK: - Cache

    @Test("Discovery result is cached and returned on second call")
    func discoverCachesResult() async {
        let session = MockURLSession()
        let url = "https://autoconfig.thunderbird.net/v1.1/fastmail.com"
        let httpResponse = HTTPURLResponse(
            url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        session.responses[url] = (Self.fastmailISPDBXML.data(using: .utf8)!, httpResponse)

        let sut = ProviderDiscovery(urlSession: session)

        // First call
        let first = await sut.discover(for: "user@fastmail.com")
        #expect(first?.source == .ispdb)
        let firstRequestCount = session.requestedURLs.count

        // Second call — should use cache
        let second = await sut.discover(for: "another@fastmail.com")
        #expect(second?.source == .ispdb)
        #expect(second?.imapHost == "imap.fastmail.com")
        // No additional network requests
        #expect(session.requestedURLs.count == firstRequestCount)
    }

    @Test("Static registry results are also cached")
    func discoverCachesStaticRegistry() async {
        let session = MockURLSession()
        let sut = ProviderDiscovery(urlSession: session)

        _ = await sut.discover(for: "user@gmail.com")
        _ = await sut.discover(for: "other@gmail.com")

        // No network requests for static registry
        #expect(session.requestedURLs.isEmpty)
    }

    @Test("Cache can be cleared for a specific domain")
    func clearCacheForDomain() async {
        let session = MockURLSession()
        let url = "https://autoconfig.thunderbird.net/v1.1/fastmail.com"
        let httpResponse = HTTPURLResponse(
            url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        session.responses[url] = (Self.fastmailISPDBXML.data(using: .utf8)!, httpResponse)

        let sut = ProviderDiscovery(urlSession: session)

        _ = await sut.discover(for: "user@fastmail.com")
        #expect(session.requestedURLs.count == 1)

        await sut.clearCache(for: "fastmail.com")

        _ = await sut.discover(for: "user@fastmail.com")
        // Should have made another request after cache clear
        #expect(session.requestedURLs.count == 2)
    }

    // MARK: - ISPDB XML Parser

    @Test("ISPDBXMLParser extracts incoming and outgoing servers")
    func parseISPDBXML() {
        let data = Self.fastmailISPDBXML.data(using: .utf8)!
        let parser = ISPDBXMLParser(data: data)

        #expect(parser.parse() == true)
        #expect(parser.displayName == "Fastmail")
        #expect(parser.incomingServer?.hostname == "imap.fastmail.com")
        #expect(parser.incomingServer?.port == 993)
        #expect(parser.incomingServer?.socketType == "SSL")
        #expect(parser.outgoingServer?.hostname == "smtp.fastmail.com")
        #expect(parser.outgoingServer?.port == 465)
        #expect(parser.outgoingServer?.socketType == "SSL")
    }

    @Test("ISPDBXMLParser extracts STARTTLS socket type")
    func parseISPDBXML_STARTTLS() {
        let data = Self.starttlsISPDBXML.data(using: .utf8)!
        let parser = ISPDBXMLParser(data: data)

        #expect(parser.parse() == true)
        #expect(parser.incomingServer?.socketType == "STARTTLS")
        #expect(parser.outgoingServer?.socketType == "STARTTLS")
    }

    @Test("ISPDBXMLParser returns false for incomplete XML")
    func parseISPDBXML_Incomplete() {
        let data = Self.incompleteISPDBXML.data(using: .utf8)!
        let parser = ISPDBXMLParser(data: data)

        #expect(parser.parse() == false)
        #expect(parser.incomingServer == nil) // only POP3, no IMAP
    }

    @Test("ISPDBXMLParser handles empty data")
    func parseISPDBXML_Empty() {
        let parser = ISPDBXMLParser(data: Data())
        #expect(parser.parse() == false)
    }

    // MARK: - Edge Cases

    @Test("Discover returns nil for invalid email")
    func discoverInvalidEmail() async {
        let session = MockURLSession()
        let sut = ProviderDiscovery(urlSession: session)

        let result = await sut.discover(for: "not-an-email")

        #expect(result == nil)
    }

    @Test("Discover returns nil for empty email")
    func discoverEmptyEmail() async {
        let session = MockURLSession()
        let sut = ProviderDiscovery(urlSession: session)

        let result = await sut.discover(for: "")

        #expect(result == nil)
    }

    @Test("Discover handles email with @ but empty domain")
    func discoverEmptyDomain() async {
        let session = MockURLSession()
        let sut = ProviderDiscovery(urlSession: session)

        let result = await sut.discover(for: "user@")

        #expect(result == nil)
    }

    // MARK: - ProviderConfiguration.toDiscoveredConfig

    @Test("ProviderConfiguration converts to DiscoveredConfig correctly")
    func providerConfigToDiscoveredConfig() {
        let config = ProviderRegistry.gmail.toDiscoveredConfig()

        #expect(config.imapHost == "imap.gmail.com")
        #expect(config.imapPort == 993)
        #expect(config.imapSecurity == .tls)
        #expect(config.smtpHost == "smtp.gmail.com")
        #expect(config.smtpPort == 465)
        #expect(config.smtpSecurity == .tls)
        #expect(config.authMethod == .xoauth2)
        #expect(config.source == .staticRegistry)
        #expect(config.displayName == "Gmail")
    }

    // MARK: - ISPDB Authentication Parsing (F2)

    @Test("ISPDBXMLParser extracts authentication element")
    func parseISPDBXML_Authentication() {
        let data = Self.fastmailISPDBXML.data(using: .utf8)!
        let parser = ISPDBXMLParser(data: data)

        #expect(parser.parse() == true)
        #expect(parser.incomingServer?.authentication == "password-cleartext")
        #expect(parser.outgoingServer?.authentication == "password-cleartext")
    }

    @Test("ISPDBXMLParser extracts OAuth2 authentication")
    func parseISPDBXML_OAuth2Authentication() {
        let data = Self.oauth2ISPDBXML.data(using: .utf8)!
        let parser = ISPDBXMLParser(data: data)

        #expect(parser.parse() == true)
        #expect(parser.incomingServer?.authentication == "OAuth2")
        #expect(parser.outgoingServer?.authentication == "OAuth2")
    }

    @Test("ISPDB OAuth2 auth maps to xoauth2 AuthMethod")
    func discoverISPDB_OAuth2AuthMethod() async {
        let session = MockURLSession()
        let url = "https://autoconfig.thunderbird.net/v1.1/oauth-provider.com"
        let httpResponse = HTTPURLResponse(
            url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        session.responses[url] = (Self.oauth2ISPDBXML.data(using: .utf8)!, httpResponse)

        let sut = ProviderDiscovery(urlSession: session)
        let result = await sut.discover(for: "user@oauth-provider.com")

        #expect(result?.source == .ispdb)
        #expect(result?.authMethod == .xoauth2)
    }

    @Test("ISPDB password-cleartext auth maps to plain AuthMethod")
    func discoverISPDB_PlainAuthMethod() async {
        let session = MockURLSession()
        let url = "https://autoconfig.thunderbird.net/v1.1/fastmail.com"
        let httpResponse = HTTPURLResponse(
            url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        session.responses[url] = (Self.fastmailISPDBXML.data(using: .utf8)!, httpResponse)

        let sut = ProviderDiscovery(urlSession: session)
        let result = await sut.discover(for: "user@fastmail.com")

        #expect(result?.source == .ispdb)
        #expect(result?.authMethod == .plain)
    }

    @Test("mapAuthentication handles all known ISPDB auth values")
    func mapAuthenticationValues() {
        // OAuth variants → .xoauth2
        #expect(ProviderDiscovery.mapAuthentication("OAuth2") == .xoauth2)
        #expect(ProviderDiscovery.mapAuthentication("oauth2") == .xoauth2)
        #expect(ProviderDiscovery.mapAuthentication("XOAUTH2") == .xoauth2)
        #expect(ProviderDiscovery.mapAuthentication("xoauth2") == .xoauth2)

        // Password variants → .plain
        #expect(ProviderDiscovery.mapAuthentication("password-cleartext") == .plain)
        #expect(ProviderDiscovery.mapAuthentication("plain") == .plain)
        #expect(ProviderDiscovery.mapAuthentication("password-encrypted") == .plain)
        #expect(ProviderDiscovery.mapAuthentication("CRAM-MD5") == .plain)

        // nil/unknown → .plain (safe default)
        #expect(ProviderDiscovery.mapAuthentication(nil) == .plain)
        #expect(ProviderDiscovery.mapAuthentication("unknown-method") == .plain)
        #expect(ProviderDiscovery.mapAuthentication("") == .plain)
    }
}
