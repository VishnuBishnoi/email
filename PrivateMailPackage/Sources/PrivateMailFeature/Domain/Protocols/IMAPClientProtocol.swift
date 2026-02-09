import Foundation

// MARK: - Data Transfer Objects

/// Simplified IMAP folder info for data transfer between layers.
///
/// Spec ref: Email Sync spec FR-SYNC-01 (Folder discovery)
public struct IMAPFolderInfo: Sendable, Equatable {
    /// Human-readable folder name
    public let name: String
    /// Full IMAP path (e.g., "[Gmail]/Sent Mail")
    public let imapPath: String
    /// IMAP LIST attributes (e.g., "\\Inbox", "\\Sent", "\\Noselect")
    public let attributes: [String]
    /// IMAP UIDVALIDITY value for this folder
    public let uidValidity: UInt32
    /// Total message count (EXISTS) at time of SELECT
    public let messageCount: UInt32

    public init(
        name: String,
        imapPath: String,
        attributes: [String],
        uidValidity: UInt32,
        messageCount: UInt32
    ) {
        self.name = name
        self.imapPath = imapPath
        self.attributes = attributes
        self.uidValidity = uidValidity
        self.messageCount = messageCount
    }
}

/// Simplified IMAP email header for data transfer.
///
/// Spec ref: Email Sync spec FR-SYNC-01 (Email sync), AC-F-05
public struct IMAPEmailHeader: Sendable, Equatable {
    /// IMAP UID for this message in the selected folder
    public let uid: UInt32
    /// RFC 2822 Message-ID header
    public let messageId: String?
    /// In-Reply-To header (parent Message-ID)
    public let inReplyTo: String?
    /// References header (space-delimited Message-IDs)
    public let references: String?
    /// From address
    public let from: String?
    /// To addresses
    public let to: [String]
    /// CC addresses
    public let cc: [String]
    /// BCC addresses
    public let bcc: [String]
    /// Email subject
    public let subject: String?
    /// Date from the envelope
    public let date: Date?
    /// IMAP flags (e.g., "\\Seen", "\\Flagged")
    public let flags: [String]
    /// RFC822.SIZE
    public let size: UInt32

    public init(
        uid: UInt32,
        messageId: String?,
        inReplyTo: String?,
        references: String?,
        from: String?,
        to: [String] = [],
        cc: [String] = [],
        bcc: [String] = [],
        subject: String?,
        date: Date?,
        flags: [String] = [],
        size: UInt32 = 0
    ) {
        self.uid = uid
        self.messageId = messageId
        self.inReplyTo = inReplyTo
        self.references = references
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.date = date
        self.flags = flags
        self.size = size
    }
}

/// Simplified IMAP email body for data transfer.
///
/// Spec ref: Email Sync spec FR-SYNC-01 (Body format handling)
public struct IMAPEmailBody: Sendable, Equatable {
    /// IMAP UID for this message
    public let uid: UInt32
    /// Plain text body part (text/plain)
    public let plainText: String?
    /// HTML body part (text/html)
    public let htmlText: String?
    /// Attachment metadata extracted from BODYSTRUCTURE
    public let attachments: [IMAPAttachmentInfo]

    public init(
        uid: UInt32,
        plainText: String?,
        htmlText: String?,
        attachments: [IMAPAttachmentInfo] = []
    ) {
        self.uid = uid
        self.plainText = plainText
        self.htmlText = htmlText
        self.attachments = attachments
    }
}

/// Attachment metadata from BODYSTRUCTURE (not downloaded during sync).
///
/// Spec ref: Email Sync spec FR-SYNC-08
public struct IMAPAttachmentInfo: Sendable, Equatable {
    /// MIME part ID (e.g., "1.2")
    public let partId: String
    /// Filename from Content-Disposition
    public let filename: String?
    /// MIME type (e.g., "application/pdf")
    public let mimeType: String?
    /// Size in bytes
    public let sizeBytes: UInt32?
    /// Content-ID for inline attachments
    public let contentId: String?

    public init(
        partId: String,
        filename: String?,
        mimeType: String?,
        sizeBytes: UInt32?,
        contentId: String?
    ) {
        self.partId = partId
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.contentId = contentId
    }
}

// MARK: - Protocol

/// Protocol for IMAP client operations.
///
/// Implementations live in the Data layer. The SyncEngine depends only
/// on this protocol (AI-01: dependency inversion).
///
/// Spec ref: Email Sync spec FR-SYNC-01, FR-SYNC-03, FR-SYNC-09
///           Validation ref: AC-F-05
public protocol IMAPClientProtocol: Sendable {

    /// Connects to the IMAP server using TLS and authenticates with XOAUTH2.
    ///
    /// - Parameters:
    ///   - host: IMAP server hostname (e.g., "imap.gmail.com")
    ///   - port: IMAP server port (993 for implicit TLS, per FR-SYNC-09)
    ///   - email: User's email address for XOAUTH2
    ///   - accessToken: OAuth 2.0 access token for XOAUTH2
    /// - Throws: `IMAPError.connectionFailed` if TLS handshake fails,
    ///           `IMAPError.authenticationFailed` if XOAUTH2 is rejected,
    ///           `IMAPError.timeout` if connection exceeds 30 seconds.
    func connect(host: String, port: Int, email: String, accessToken: String) async throws

    /// Disconnects from the IMAP server gracefully.
    func disconnect() async throws

    /// Whether the client is currently connected and authenticated.
    var isConnected: Bool { get async }

    /// Lists all available IMAP folders with their attributes.
    ///
    /// Maps to IMAP `LIST "" "*"` command.
    /// Spec ref: FR-SYNC-01 step 1 (Folder discovery)
    func listFolders() async throws -> [IMAPFolderInfo]

    /// Selects a folder for subsequent operations.
    ///
    /// - Parameter imapPath: The IMAP path of the folder (e.g., "INBOX")
    /// - Returns: Tuple of UIDVALIDITY and EXISTS count
    /// - Throws: `IMAPError.folderNotFound` if the folder doesn't exist
    func selectFolder(_ imapPath: String) async throws -> (uidValidity: UInt32, messageCount: UInt32)

    /// Searches for message UIDs since a given date in the currently selected folder.
    ///
    /// Maps to IMAP `SEARCH SINCE <date>` command.
    /// Spec ref: FR-SYNC-01 step 2
    func searchUIDs(since date: Date) async throws -> [UInt32]

    /// Fetches email headers for specified UIDs in the currently selected folder.
    ///
    /// Maps to IMAP `FETCH <UIDs> (ENVELOPE FLAGS BODYSTRUCTURE RFC822.SIZE)`.
    /// Spec ref: FR-SYNC-01 step 2, AC-F-05
    func fetchHeaders(uids: [UInt32]) async throws -> [IMAPEmailHeader]

    /// Fetches email bodies for specified UIDs in the currently selected folder.
    ///
    /// Maps to IMAP `FETCH <UIDs> (BODY[text/plain] BODY[text/html])`.
    /// Spec ref: FR-SYNC-01 step 3
    func fetchBodies(uids: [UInt32]) async throws -> [IMAPEmailBody]

    /// Fetches current flags for specified UIDs.
    ///
    /// Maps to IMAP `FETCH <UIDs> (FLAGS)`.
    /// Spec ref: FR-SYNC-10 (Server → Local pull)
    func fetchFlags(uids: [UInt32]) async throws -> [UInt32: [String]]

    /// Stores (adds/removes) flags on a message.
    ///
    /// Spec ref: FR-SYNC-10 (Local → Server push)
    func storeFlags(
        uid: UInt32,
        add: [String],
        remove: [String]
    ) async throws

    /// Copies messages to another folder.
    ///
    /// Spec ref: FR-SYNC-10 (Archive/Delete behavior — COPY step)
    func copyMessages(uids: [UInt32], to destinationPath: String) async throws

    /// Permanently removes messages from the currently selected folder.
    ///
    /// Sets \\Deleted flag and EXPUNGEs.
    /// Spec ref: FR-SYNC-10 (Archive/Delete behavior — DELETE+EXPUNGE step)
    func expungeMessages(uids: [UInt32]) async throws

    /// Appends a raw MIME message to a folder.
    ///
    /// Used to copy sent messages to the Sent folder (FR-SYNC-07).
    func appendMessage(to imapPath: String, messageData: Data, flags: [String]) async throws

    /// Fetches a single body part (attachment) by UID and MIME section.
    ///
    /// Maps to IMAP `UID FETCH <uid> (BODY.PEEK[<section>])`.
    /// Returns the raw body part data (still transfer-encoded).
    ///
    /// Spec ref: FR-SYNC-08 (Lazy attachment download)
    func fetchBodyPart(uid: UInt32, section: String) async throws -> Data

    /// Starts IMAP IDLE on the currently selected folder.
    ///
    /// The handler is called when the server sends an EXISTS notification.
    /// Must re-issue IDLE every 25 minutes (Gmail drops after ~29 min).
    ///
    /// Spec ref: FR-SYNC-03 (Real-time updates)
    func startIDLE(onNewMail: @Sendable @escaping () -> Void) async throws

    /// Stops IMAP IDLE.
    func stopIDLE() async throws
}
