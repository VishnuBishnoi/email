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

    /// Offline send queue max age in hours (FR-SYNC-07 step 5: 24 hours)
    public static let sendQueueMaxAgeHours = 24

    /// Maximum send retry attempts before marking as failed
    public static let maxSendRetryCount = 3

    /// Gmail IMAP defaults
    public static let gmailImapHost = "imap.gmail.com"
    public static let gmailImapPort = 993
    public static let gmailSmtpHost = "smtp.gmail.com"
    public static let gmailSmtpPort = 465

    // MARK: - OAuth Configuration (FR-ACCT-03, FR-ACCT-04)

    /// Maximum token refresh retry attempts before prompting re-auth
    public static let oauthRetryCount = 3
    /// Base delay for exponential backoff on refresh retry (seconds)
    public static let oauthRetryBaseDelay: TimeInterval = 1.0
    /// Buffer before token expiry to trigger proactive refresh (seconds)
    public static let tokenRefreshBuffer: TimeInterval = 300

    /// Google OAuth 2.0 authorization endpoint
    public static let googleAuthEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    /// Google OAuth 2.0 token endpoint
    public static let googleTokenEndpoint = "https://oauth2.googleapis.com/token"
    /// Google OAuth 2.0 client ID (iOS app type, from Google Cloud Console)
    public static let oauthClientId = "694609716333-3c3jmr5khlp6gei3b1nbl76k1tn3vf03.apps.googleusercontent.com"
    /// OAuth scope for Gmail IMAP/SMTP access + user profile (FR-ACCT-01)
    public static let oauthScope = "https://mail.google.com/ email profile"
    /// Custom URL scheme for OAuth redirect (reversed client ID per Google's iOS requirements)
    public static let oauthRedirectScheme = "com.googleusercontent.apps.694609716333-3c3jmr5khlp6gei3b1nbl76k1tn3vf03"

    // MARK: - IMAP Connection Management (FR-SYNC-09)

    /// Connection timeout in seconds (FR-SYNC-09)
    public static let imapConnectionTimeout: TimeInterval = 30.0
    /// Maximum concurrent IMAP connections per account (FR-SYNC-09, Gmail limit)
    public static let imapMaxConnectionsPerAccount = 5
    /// Retry base delay in seconds for exponential backoff (FR-SYNC-09: 5s, 15s, 45s)
    public static let imapRetryBaseDelay: TimeInterval = 5.0
    /// Maximum retry attempts (FR-SYNC-09)
    public static let imapMaxRetries = 3
    /// IMAP IDLE re-issue interval in seconds (FR-SYNC-03: 25 min, Gmail drops at ~29 min)
    public static let imapIdleRefreshInterval: TimeInterval = 25 * 60
    /// Maximum email body size in bytes (FR-SYNC-01: 10 MB)
    public static let maxEmailBodySizeBytes = 10 * 1024 * 1024

    // MARK: - Thread List (FR-TL-01)

    /// Number of threads per page for cursor-based pagination (FR-TL-01)
    public static let threadListPageSize = 25

    // MARK: - Composer (FR-COMP-01, FR-COMP-02, FR-COMP-04)

    /// Draft auto-save interval in seconds (FR-COMP-01)
    public static let draftAutoSaveIntervalSeconds = 30
    /// Maximum total attachment size in MB before warning (FR-COMP-01)
    public static let maxAttachmentSizeMB = 25
    /// Maximum contact autocomplete suggestions to display (FR-COMP-04)
    public static let contactAutocompleteLimitItems = 10
    /// Maximum smart reply suggestions (FR-COMP-03)
    public static let smartReplyMaxSuggestions = 3
    /// SMTP retry delays in seconds: 30s, 2m, 8m (FR-SYNC-07)
    public static let sendRetryDelays: [TimeInterval] = [30, 120, 480]
}
