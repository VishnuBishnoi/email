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

    /// Parent email
    public var email: Email?

    public init(
        id: String = UUID().uuidString,
        filename: String,
        mimeType: String,
        sizeBytes: Int = 0,
        localPath: String? = nil,
        isDownloaded: Bool = false
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.localPath = localPath
        self.isDownloaded = isDownloaded
    }
}
