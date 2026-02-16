import Foundation
import UniformTypeIdentifiers

/// Shared utilities for attachment filename resolution and content-encoding detection.
///
/// Consolidates logic previously duplicated across `SyncEmailsUseCase`,
/// `DownloadAttachmentUseCase`, and `AttachmentPreviewFileStore`.
enum AttachmentFileUtilities {

    // MARK: - Filename Resolution

    /// Returns `filename` with a file extension appended when one is missing.
    ///
    /// Resolution order:
    /// 1. If the filename already has an extension, return it as-is.
    /// 2. Derive extension from `mimeType` via `UTType`.
    /// 3. Return the filename unchanged.
    static func resolvedFilename(
        _ filename: String,
        mimeType: String?,
        fallbackName: String = "attachment"
    ) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? fallbackName : trimmed

        guard URL(fileURLWithPath: base).pathExtension.isEmpty else {
            return base
        }

        if let mimeType,
           let utType = UTType(mimeType: mimeType),
           let ext = utType.preferredFilenameExtension,
           !ext.isEmpty {
            return "\(base).\(ext)"
        }

        return base
    }

    // MARK: - Base64 Detection

    /// Returns `true` when every byte in `sample` is a valid base64 character
    /// (A-Z, a-z, 0-9, +, /, =) or a line-break (CR/LF).
    static func looksLikeBase64(_ sample: some Collection<UInt8>) -> Bool {
        sample.allSatisfy(isBase64OrWhitespaceByte)
    }

    /// Checks a single byte against the base64 alphabet (no whitespace).
    static func isBase64Byte(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90)    // A-Z
            || (byte >= 97 && byte <= 122) // a-z
            || (byte >= 48 && byte <= 57)  // 0-9
            || byte == 43  // +
            || byte == 47  // /
            || byte == 61  // =
    }

    // MARK: - Private

    private static func isBase64OrWhitespaceByte(_ byte: UInt8) -> Bool {
        isBase64Byte(byte)
            || byte == 13  // \r
            || byte == 10  // \n
    }
}
