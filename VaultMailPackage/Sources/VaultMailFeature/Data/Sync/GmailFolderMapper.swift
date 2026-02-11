import Foundation

/// Maps Gmail-specific IMAP folder attributes and paths to our generic FolderType.
///
/// Spec ref: Email Sync spec FR-SYNC-01 step 1 (Folder discovery)
public enum GmailFolderMapper {

    /// Maps an IMAP folder's attributes and path to a `FolderType`.
    ///
    /// Gmail special-use attribute mapping per FR-SYNC-01:
    /// - `\Inbox`   → `.inbox`
    /// - `\Sent`    → `.sent`
    /// - `\Drafts`  → `.drafts`
    /// - `\Trash`   → `.trash`
    /// - `\Junk`    → `.spam`
    /// - `\Flagged` → `.starred`
    /// - `\All`     → `.archive` (but MUST NOT be synced)
    /// - User labels → `.custom`
    public static func folderType(
        imapPath: String,
        attributes: [String]
    ) -> FolderType {
        let lowered = Set(attributes.map { $0.lowercased() })

        if lowered.contains("\\inbox") || imapPath.uppercased() == "INBOX" {
            return .inbox
        }
        if lowered.contains("\\sent") {
            return .sent
        }
        if lowered.contains("\\drafts") {
            return .drafts
        }
        if lowered.contains("\\trash") {
            return .trash
        }
        if lowered.contains("\\junk") {
            return .spam
        }
        if lowered.contains("\\flagged") {
            return .starred
        }
        if lowered.contains("\\all") {
            return .archive
        }

        // Fallback: match by well-known Gmail IMAP paths
        switch imapPath {
        case "[Gmail]/Sent Mail":
            return .sent
        case "[Gmail]/Drafts":
            return .drafts
        case "[Gmail]/Trash":
            return .trash
        case "[Gmail]/Spam":
            return .spam
        case "[Gmail]/Starred":
            return .starred
        case "[Gmail]/All Mail":
            return .archive
        default:
            return .custom
        }
    }

    /// Determines whether a folder should be synced.
    ///
    /// Per FR-SYNC-01:
    /// - `[Gmail]/All Mail` (`\All`) → MUST NOT be synced (redundant)
    /// - `[Gmail]/Important` → MUST NOT be synced (importance is a flag)
    /// - Folders with `\Noselect` → cannot be opened, skip
    public static func shouldSync(
        imapPath: String,
        attributes: [String]
    ) -> Bool {
        let lowered = Set(attributes.map { $0.lowercased() })

        // \Noselect means the folder can't be opened
        if lowered.contains("\\noselect") {
            return false
        }

        // \All (Gmail All Mail) is redundant
        if lowered.contains("\\all") {
            return false
        }

        // \Important → MUST NOT be synced as a folder; importance is a flag, not a mailbox (FR-SYNC-01)
        if lowered.contains("\\important") {
            return false
        }

        // Gmail Important is a flag, not a real folder (path fallback)
        if imapPath == "[Gmail]/Important" {
            return false
        }

        // Also skip All Mail by path (in case attribute is missing)
        if imapPath == "[Gmail]/All Mail" {
            return false
        }

        return true
    }
}
