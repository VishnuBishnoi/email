import Foundation

/// Use case for downloading email attachments.
///
/// V1 stub: simulates download since IMAP attachment fetch isn't built yet.
///
/// Spec ref: Email Detail FR-ED-03
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

    public init(repository: EmailRepositoryProtocol) {
        self.repository = repository
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
        // V1 stub: simulate download
        do {
            try await Task.sleep(for: .seconds(1))
            let path = NSTemporaryDirectory() + attachment.filename
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
}
