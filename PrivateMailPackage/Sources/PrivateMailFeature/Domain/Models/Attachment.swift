import Foundation
import SwiftData

/// A file attachment belonging to an email.
///
/// Spec ref: Foundation spec Section 5.1
@Model
public final class Attachment {
    /// Unique identifier (UUID string)
    @Attribute(.unique) public var id: String
    /// Original filename
    public var filename: String
    /// MIME type (e.g., "application/pdf")
    public var mimeType: String
    /// File size in bytes
    public var sizeBytes: Int
    /// Local file path (nil if not downloaded)
    public var localPath: String?
    /// Whether the attachment has been downloaded locally
    public var isDownloaded: Bool
    /// MIME body section identifier from BODYSTRUCTURE (e.g. "1.2").
    /// Used by IMAP FETCH to download this specific part (FR-SYNC-08).
    public var bodySection: String?
    /// Content-Transfer-Encoding (e.g. "base64", "quoted-printable", "7bit")
    public var transferEncoding: String?
    /// Content-ID for inline attachments (e.g. "<cid:image001>")
    public var contentId: String?

    /// Parent email
    public var email: Email?

    public init(
        id: String = UUID().uuidString,
        filename: String,
        mimeType: String,
        sizeBytes: Int = 0,
        localPath: String? = nil,
        isDownloaded: Bool = false,
        bodySection: String? = nil,
        transferEncoding: String? = nil,
        contentId: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.localPath = localPath
        self.isDownloaded = isDownloaded
        self.bodySection = bodySection
        self.transferEncoding = transferEncoding
        self.contentId = contentId
    }
}
