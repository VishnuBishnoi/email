import Foundation
import SwiftData

/// An individual email message.
///
/// Multi-value field serialization (Section 5.6):
/// - `toAddresses`, `ccAddresses`, `bccAddresses`: JSON array of strings
/// - `references`: space-delimited Message-IDs per RFC 2822
///
/// Spec ref: Foundation spec Section 5.1
@Model
public final class Email {
    /// Unique identifier (UUID string)
    @Attribute(.unique) public var id: String
    /// Account ID this email belongs to
    public var accountId: String
    /// Thread ID this email belongs to
    public var threadId: String
    /// RFC 2822 Message-ID header
    public var messageId: String
    /// In-Reply-To header (Message-ID of parent)
    public var inReplyTo: String?
    /// References header (space-delimited Message-IDs per RFC 2822)
    public var references: String?
    /// Sender email address
    public var fromAddress: String
    /// Sender display name
    public var fromName: String?
    /// To recipients (JSON array of strings)
    public var toAddresses: String
    /// CC recipients (JSON array of strings)
    public var ccAddresses: String?
    /// BCC recipients (JSON array of strings)
    public var bccAddresses: String?
    /// Email subject line
    public var subject: String
    /// Plain text body (stored externally for large blobs)
    @Attribute(.externalStorage) public var bodyPlain: String?
    /// HTML body (stored externally for large blobs)
    @Attribute(.externalStorage) public var bodyHTML: String?
    /// Short preview snippet
    public var snippet: String?
    /// Date the email was received
    public var dateReceived: Date?
    /// Date the email was sent
    public var dateSent: Date?
    /// Whether the email has been read
    public var isRead: Bool
    /// Whether the email is starred/flagged
    public var isStarred: Bool
    /// Whether this is a draft
    public var isDraft: Bool
    /// Whether this email is marked for deletion
    public var isDeleted: Bool
    /// AI-assigned category (raw value of AICategory)
    public var aiCategory: String?
    /// AI-generated summary
    public var aiSummary: String?
    /// Whether this email is flagged as spam/phishing by AI detection.
    /// Never auto-deleted; displayed as visual warning only. User can override.
    /// Spec ref: FR-AI-06
    public var isSpam: Bool
    /// Raw Authentication-Results header from IMAP (SPF/DKIM/DMARC).
    /// Stored as the full header value string for RuleEngine analysis.
    /// Populated during IMAP sync from the email's headers.
    /// Spec ref: FR-AI-06 (header authentication signal)
    public var authenticationResults: String?
    /// Email size in bytes
    public var sizeBytes: Int
    /// Send pipeline state (raw value of SendState)
    public var sendState: String
    /// Number of send retry attempts
    public var sendRetryCount: Int
    /// Date the email was queued for sending
    public var sendQueuedDate: Date?

    /// Parent thread
    public var thread: Thread?

    /// Folder associations (join table for many-to-many Email↔Folder).
    /// Cascade: deleting an Email deletes its EmailFolder join entries (FR-FOUND-03).
    @Relationship(deleteRule: .cascade, inverse: \EmailFolder.email)
    public var emailFolders: [EmailFolder]

    /// Attachments for this email.
    /// Cascade: deleting an Email deletes all Attachments (FR-FOUND-03).
    @Relationship(deleteRule: .cascade, inverse: \Attachment.email)
    public var attachments: [Attachment]

    public init(
        id: String = UUID().uuidString,
        accountId: String,
        threadId: String,
        messageId: String,
        inReplyTo: String? = nil,
        references: String? = nil,
        fromAddress: String,
        fromName: String? = nil,
        toAddresses: String = "[]",
        ccAddresses: String? = nil,
        bccAddresses: String? = nil,
        subject: String,
        bodyPlain: String? = nil,
        bodyHTML: String? = nil,
        snippet: String? = nil,
        dateReceived: Date? = nil,
        dateSent: Date? = nil,
        isRead: Bool = false,
        isStarred: Bool = false,
        isDraft: Bool = false,
        isDeleted: Bool = false,
        aiCategory: String? = AICategory.uncategorized.rawValue,
        aiSummary: String? = nil,
        isSpam: Bool = false,
        authenticationResults: String? = nil,
        sizeBytes: Int = 0,
        sendState: String = SendState.none.rawValue,
        sendRetryCount: Int = 0,
        sendQueuedDate: Date? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.threadId = threadId
        self.messageId = messageId
        self.inReplyTo = inReplyTo
        self.references = references
        self.fromAddress = fromAddress
        self.fromName = fromName
        self.toAddresses = toAddresses
        self.ccAddresses = ccAddresses
        self.bccAddresses = bccAddresses
        self.subject = subject
        self.bodyPlain = bodyPlain
        self.bodyHTML = bodyHTML
        self.snippet = snippet
        self.dateReceived = dateReceived
        self.dateSent = dateSent
        self.isRead = isRead
        self.isStarred = isStarred
        self.isDraft = isDraft
        self.isDeleted = isDeleted
        self.aiCategory = aiCategory
        self.aiSummary = aiSummary
        self.isSpam = isSpam
        self.authenticationResults = authenticationResults
        self.sizeBytes = sizeBytes
        self.sendState = sendState
        self.sendRetryCount = sendRetryCount
        self.sendQueuedDate = sendQueuedDate
        self.emailFolders = []
        self.attachments = []
    }
}
