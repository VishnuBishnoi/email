import Foundation

/// Provider-agnostic folder mapper using a 3-tier resolution strategy.
///
/// Replaces `GmailFolderMapper` with a universal approach:
/// 1. **RFC 6154 attributes** (`\Sent`, `\Drafts`, `\Trash`, etc.) — works for ALL providers
/// 2. **Provider-specific path maps** — well-known paths per provider
/// 3. **Name heuristics** — case-insensitive keyword matching
///
/// Spec ref: FR-MPROV-11 (Provider-Agnostic Folder Mapping)
public enum ProviderFolderMapper {

    /// Maps an IMAP folder's attributes, path, and provider to a `FolderType`.
    ///
    /// Resolution order:
    /// 1. RFC 6154 special-use attributes (universal)
    /// 2. Provider-specific well-known paths
    /// 3. Case-insensitive name heuristics
    /// 4. Fallback to `.custom`
    public static func folderType(
        imapPath: String,
        attributes: [String],
        provider: ProviderIdentifier = .gmail
    ) -> FolderType {
        // Tier 1: RFC 6154 attributes (universal, highest priority)
        if let type = mapFromAttributes(attributes, imapPath: imapPath) {
            return type
        }

        // Tier 2: Provider-specific well-known paths
        if let type = mapFromProviderPath(imapPath, provider: provider) {
            return type
        }

        // Tier 3: Name heuristics (case-insensitive)
        if let type = mapFromNameHeuristic(imapPath) {
            return type
        }

        return .custom
    }

    /// Determines whether a folder should be synced.
    ///
    /// Excludes:
    /// - Folders with `\Noselect` (can't be opened)
    /// - `\All` / All Mail (redundant on Gmail, safe to skip elsewhere)
    /// - `\Important` / `[Gmail]/Important` (importance is a flag, not a mailbox)
    public static func shouldSync(
        imapPath: String,
        attributes: [String],
        provider: ProviderIdentifier = .gmail
    ) -> Bool {
        let lowered = Set(attributes.map { $0.lowercased() })

        // \Noselect means the folder can't be opened
        if lowered.contains("\\noselect") {
            return false
        }

        // \All (Gmail All Mail, iCloud Archive) is redundant to sync
        if lowered.contains("\\all") {
            return false
        }

        // \Important → importance is a flag, not a mailbox
        if lowered.contains("\\important") {
            return false
        }

        // Gmail-specific path exclusions (in case attributes are missing)
        if provider == .gmail {
            if imapPath == "[Gmail]/Important" || imapPath == "[Gmail]/All Mail" {
                return false
            }
        }

        return true
    }

    // MARK: - Tier 1: RFC 6154 Attributes

    private static func mapFromAttributes(_ attributes: [String], imapPath: String) -> FolderType? {
        let lowered = Set(attributes.map { $0.lowercased() })

        // INBOX check (both attribute and path)
        if lowered.contains("\\inbox") || imapPath.uppercased() == "INBOX" {
            return .inbox
        }
        if lowered.contains("\\sent") { return .sent }
        if lowered.contains("\\drafts") { return .drafts }
        if lowered.contains("\\trash") { return .trash }
        if lowered.contains("\\junk") { return .spam }
        if lowered.contains("\\flagged") { return .starred }
        if lowered.contains("\\all") { return .archive }
        // \Archive attribute (RFC 6154)
        if lowered.contains("\\archive") { return .archive }

        return nil
    }

    // MARK: - Tier 2: Provider-Specific Paths

    private static func mapFromProviderPath(_ imapPath: String, provider: ProviderIdentifier) -> FolderType? {
        let knownPaths: [String: FolderType]

        switch provider {
        case .gmail:
            knownPaths = [
                "[Gmail]/Sent Mail": .sent,
                "[Gmail]/Drafts": .drafts,
                "[Gmail]/Trash": .trash,
                "[Gmail]/Spam": .spam,
                "[Gmail]/Starred": .starred,
                "[Gmail]/All Mail": .archive,
            ]
        case .outlook:
            knownPaths = [
                "Sent Items": .sent,
                "Drafts": .drafts,
                "Deleted Items": .trash,
                "Junk Email": .spam,
                "Archive": .archive,
            ]
        case .yahoo:
            knownPaths = [
                "Sent": .sent,
                "Draft": .drafts,
                "Trash": .trash,
                "Bulk Mail": .spam,
                "Archive": .archive,
            ]
        case .icloud:
            knownPaths = [
                "Sent Messages": .sent,
                "Drafts": .drafts,
                "Deleted Messages": .trash,
                "Junk": .spam,
                "Archive": .archive,
            ]
        case .custom:
            // Custom providers rely on attributes and heuristics only
            knownPaths = [:]
        }

        return knownPaths[imapPath]
    }

    // MARK: - Tier 3: Name Heuristics

    private static func mapFromNameHeuristic(_ imapPath: String) -> FolderType? {
        // Extract the final component (e.g., "[Gmail]/Sent Mail" → "Sent Mail")
        let name: String
        if let lastSlash = imapPath.lastIndex(of: "/") {
            name = String(imapPath[imapPath.index(after: lastSlash)...])
        } else {
            name = imapPath
        }
        let lower = name.lowercased()

        // Inbox is always uppercase INBOX per RFC 3501
        if lower == "inbox" { return .inbox }

        // Sent
        if lower.contains("sent") { return .sent }

        // Drafts
        if lower.contains("draft") { return .drafts }

        // Trash / Deleted / Recycle Bin
        if lower.contains("trash") || lower.contains("deleted") || lower == "bin" || lower.contains("recycle bin") {
            return .trash
        }

        // Spam / Junk / Bulk
        if lower.contains("spam") || lower.contains("junk") || lower.contains("bulk") {
            return .spam
        }

        // Archive / All Mail
        if lower.contains("archive") || lower.contains("all mail") {
            return .archive
        }

        // Starred / Flagged
        if lower.contains("starred") || lower.contains("flagged") {
            return .starred
        }

        return nil
    }
}
