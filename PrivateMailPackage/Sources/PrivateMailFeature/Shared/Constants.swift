import Foundation

/// App-wide constants derived from the Foundation and Account Management specs.
public enum AppConstants {
    /// Default sync window in days (FR-ACCT-02)
    public static let defaultSyncWindowDays = 30

    /// Available sync window options in days (FR-ACCT-02)
    public static let syncWindowOptions = [7, 14, 30, 60, 90]

    /// Maximum supported emails per account (NFR-STOR-01)
    public static let maxEmailsPerAccount = 50_000

    /// Maximum attachment cache size in MB per account (Section 8.1)
    public static let maxAttachmentCacheMB = 500

    /// Total app storage warning threshold in GB (NFR-STOR-02)
    public static let storageWarningThresholdGB: Double = 5.0

    /// Per-account storage warning threshold in GB (NFR-STOR-01)
    public static let accountStorageWarningGB: Double = 2.0

    /// Offline send queue max age in hours (Section 8.1)
    public static let sendQueueMaxAgeHours = 72

    /// Maximum send retry attempts before marking as failed
    public static let maxSendRetryCount = 3

    /// Gmail IMAP defaults
    public static let gmailImapHost = "imap.gmail.com"
    public static let gmailImapPort = 993
    public static let gmailSmtpHost = "smtp.gmail.com"
    public static let gmailSmtpPort = 465
}
