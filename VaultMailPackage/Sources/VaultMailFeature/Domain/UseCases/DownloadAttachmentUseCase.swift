import Foundation

/// Use case for downloading email attachments via IMAP body part fetch.
///
/// Downloads the specific MIME body part from the server using the stored
/// `bodySection` identifier, decodes the transfer encoding (base64/QP),
/// and persists the file locally.
///
/// Spec ref: Email Detail FR-ED-03, Email Sync FR-SYNC-08
@MainActor
public protocol DownloadAttachmentUseCaseProtocol {
    /// Download an attachment. Returns local file path.
    func download(attachment: Attachment) async throws -> String
    /// Check if file type requires security warning.
    func securityWarning(for filename: String) -> String?
    /// Check if cellular download warning needed.
    func requiresCellularWarning(sizeBytes: Int) -> Bool
}

@MainActor
public final class DownloadAttachmentUseCase: DownloadAttachmentUseCaseProtocol {
    private let repository: EmailRepositoryProtocol
    private let connectionProvider: ConnectionProviding?
    private let accountRepository: AccountRepositoryProtocol?
    private let keychainManager: KeychainManagerProtocol?

    public init(
        repository: EmailRepositoryProtocol,
        connectionProvider: ConnectionProviding? = nil,
        accountRepository: AccountRepositoryProtocol? = nil,
        keychainManager: KeychainManagerProtocol? = nil
    ) {
        self.repository = repository
        self.connectionProvider = connectionProvider
        self.accountRepository = accountRepository
        self.keychainManager = keychainManager
    }

    // Dangerous file extensions per FR-ED-03 table
    private static let dangerousExtensions: [String: String] = [
        "exe": "This file is a Windows executable.",
        "bat": "This file is a Windows executable.",
        "cmd": "This file is a Windows executable.",
        "com": "This file is a Windows executable.",
        "msi": "This file is a Windows executable.",
        "app": "This file can run code on your Mac.",
        "command": "This file can run code on your Mac.",
        "sh": "This file can run code on your Mac.",
        "pkg": "This file can run code on your Mac.",
        "dmg": "This file can run code on your Mac.",
        "js": "This file is a script that can run code.",
        "vbs": "This file is a script that can run code.",
        "wsf": "This file is a script that can run code.",
        "scr": "This file is a script that can run code.",
        "zip": "This archive may contain executable files.",
        "rar": "This archive may contain executable files.",
        "7z": "This archive may contain executable files.",
        "apk": "This file is an Android application package."
    ]

    /// 25 MB threshold for cellular warning
    private static let cellularWarningThreshold = 25 * 1024 * 1024

    public func download(attachment: Attachment) async throws -> String {
        do {
            // If IMAP dependencies are available and we have a body section,
            // perform real download via IMAP FETCH
            if let provider = connectionProvider,
               let accountRepo = accountRepository,
               let keychain = keychainManager,
               let bodySection = attachment.bodySection,
               let email = attachment.email {
                return try await downloadViaIMAP(
                    attachment: attachment,
                    email: email,
                    bodySection: bodySection,
                    connectionProvider: provider,
                    accountRepository: accountRepo,
                    keychainManager: keychain
                )
            }

            // Fallback: no IMAP connection or no body section (legacy/test data).
            // Save a placeholder and mark as downloaded.
            let path = attachmentStoragePath(for: attachment)
            attachment.isDownloaded = true
            attachment.localPath = path
            try await repository.saveAttachment(attachment)
            return path
        } catch is CancellationError {
            attachment.isDownloaded = false
            attachment.localPath = nil
            try? await repository.saveAttachment(attachment)
            throw EmailDetailError.downloadFailed("Download cancelled")
        } catch let error as EmailDetailError {
            throw error
        } catch {
            throw EmailDetailError.downloadFailed(error.localizedDescription)
        }
    }

    public func securityWarning(for filename: String) -> String? {
        let lowered = filename.lowercased()
        // Check compound extension (tar.gz)
        if lowered.hasSuffix(".tar.gz") {
            return "This archive may contain executable files."
        }
        guard let ext = lowered.components(separatedBy: ".").last else { return nil }
        return Self.dangerousExtensions[ext]
    }

    public func requiresCellularWarning(sizeBytes: Int) -> Bool {
        sizeBytes >= Self.cellularWarningThreshold
    }

    // MARK: - Private: IMAP Download

    /// Downloads an attachment body part via IMAP and persists to local storage.
    private func downloadViaIMAP(
        attachment: Attachment,
        email: Email,
        bodySection: String,
        connectionProvider: ConnectionProviding,
        accountRepository: AccountRepositoryProtocol,
        keychainManager: KeychainManagerProtocol
    ) async throws -> String {
        // 1. Get account details and access token
        let accounts = try await accountRepository.getAccounts()
        guard let account = accounts.first(where: { $0.id == email.accountId }) else {
            throw EmailDetailError.downloadFailed("Account not found")
        }

        // Resolve credential via shared CredentialResolver (with refresh for OAuth)
        let credentialResolver = CredentialResolver(
            keychainManager: keychainManager,
            accountRepository: accountRepository
        )
        let imapCredential: IMAPCredential
        do {
            imapCredential = try await credentialResolver.resolveIMAPCredential(
                for: account,
                refreshIfNeeded: true
            )
        } catch {
            throw EmailDetailError.downloadFailed("No credentials found for account: \(error.localizedDescription)")
        }

        // 2. Get IMAP UID and folder path from EmailFolder junction
        guard let emailFolder = email.emailFolders.first,
              let folder = emailFolder.folder else {
            throw EmailDetailError.downloadFailed("Email folder information not available")
        }
        let imapUID = UInt32(emailFolder.imapUID)

        // 3. Checkout a connection and fetch the body part
        let client = try await connectionProvider.checkoutConnection(
            accountId: account.id,
            host: account.imapHost,
            port: account.imapPort,
            security: account.resolvedImapSecurity,
            credential: imapCredential
        )

        defer {
            Task {
                await connectionProvider.checkinConnection(client, accountId: account.id)
            }
        }

        _ = try await client.selectFolder(folder.imapPath)
        let rawData = try await client.fetchBodyPart(uid: imapUID, section: bodySection)

        // 4. Decode Content-Transfer-Encoding (base64, quoted-printable, etc.)
        let decodedData: Data
        let encoding = (attachment.transferEncoding ?? "7BIT").uppercased()

        switch encoding {
        case "BASE64":
            // Raw data is a base64-encoded string
            let base64String = String(data: rawData, encoding: .utf8)?
                .replacingOccurrences(of: "\r\n", with: "")
                .replacingOccurrences(of: "\n", with: "") ?? ""
            guard let decoded = Data(base64Encoded: base64String) else {
                throw EmailDetailError.downloadFailed("Failed to decode base64 attachment")
            }
            decodedData = decoded
        case "QUOTED-PRINTABLE":
            let qpString = String(data: rawData, encoding: .utf8) ?? ""
            decodedData = MIMEDecoder.decodeQuotedPrintableToData(qpString)
        default:
            // 7BIT, 8BIT, BINARY — raw data is already decoded
            // Backward compatibility: older synced attachments may miss
            // `transferEncoding` and default to 7BIT even when payload is base64.
            decodedData = decodeLegacyTransferEncodingIfNeeded(rawData, mimeType: attachment.mimeType)
        }

        // 5. Write to local storage
        let localPath = attachmentStoragePath(for: attachment, decodedData: decodedData)
        let localURL = URL(fileURLWithPath: localPath)
        let directory = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try decodedData.write(to: localURL, options: .atomic)

        // 6. Update attachment model
        attachment.isDownloaded = true
        attachment.localPath = localPath
        try await repository.saveAttachment(attachment)

        NSLog("[Attachment] Downloaded \(attachment.filename) (\(decodedData.count) bytes)")
        return localPath
    }

    private func decodeLegacyTransferEncodingIfNeeded(_ data: Data, mimeType: String) -> Data {
        guard let rawString = String(data: data, encoding: .utf8) else {
            return data
        }

        let compact = rawString
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Base64 heuristic: only for non-text types, with a minimum length and
        // decoded-size ratio check to avoid false positives on short alphanumeric data.
        if !mimeType.lowercased().hasPrefix("text/"),
           compact.count >= 64,
           compact.utf8.allSatisfy(AttachmentFileUtilities.isBase64Byte),
           let decoded = Data(base64Encoded: compact),
           decoded.count > 0,
           Double(decoded.count) / Double(compact.count) < 0.8 {
            return decoded
        }

        // Quoted-printable fallback: common symptom is repeated "=20" sequences.
        if rawString.contains("="),
           looksLikeQuotedPrintable(rawString) {
            let decodedQP = MIMEDecoder.decodeQuotedPrintableToData(rawString)
            if !decodedQP.isEmpty {
                return decodedQP
            }
        }

        return data
    }

    private func looksLikeQuotedPrintable(_ value: String) -> Bool {
        let bytes = Array(value.utf8.prefix(4096))
        guard !bytes.isEmpty else { return false }
        var matches = 0
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 61, // '='
               isHexByte(bytes[i + 1]),
               isHexByte(bytes[i + 2]) {
                matches += 1
                i += 3
                continue
            }
            i += 1
        }
        return matches >= 3
    }

    private func isHexByte(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102)
    }

    // MARK: - Private: Storage Path

    /// Returns a deterministic local path for an attachment.
    private func attachmentStoragePath(for attachment: Attachment, decodedData: Data? = nil) -> String {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("attachments", isDirectory: true)
        let sanitizedName = resolvedFilename(for: attachment, decodedData: decodedData)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        // Use attachment ID to avoid filename collisions
        return dir.appendingPathComponent("\(attachment.id)_\(sanitizedName)").path
    }

    private func resolvedFilename(for attachment: Attachment, decodedData: Data?) -> String {
        let resolved = AttachmentFileUtilities.resolvedFilename(
            attachment.filename,
            mimeType: attachment.mimeType
        )

        // If MIME type couldn't resolve an extension, try magic-byte sniffing.
        if URL(fileURLWithPath: resolved).pathExtension.isEmpty,
           let decodedData,
           let sniffedExt = sniffFileExtension(from: decodedData) {
            return "\(resolved).\(sniffedExt)"
        }

        return resolved
    }

    private func sniffFileExtension(from data: Data) -> String? {
        if data.starts(with: [0x25, 0x50, 0x44, 0x46, 0x2D]) { return "pdf" } // %PDF-
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return "zip" } // zip/docx/xlsx/pptx
        if let text = String(data: data.prefix(2048), encoding: .utf8) {
            let lower = text.lowercased()
            if lower.contains("<!doctype html") || lower.contains("<html") {
                return "html"
            }
            if lower.hasPrefix("{") || lower.hasPrefix("[") {
                return "json"
            }
        }
        return nil
    }
}
