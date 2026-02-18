import Foundation

/// Maps Gmail-specific IMAP folder attributes and paths to our generic FolderType.
///
/// **Deprecated:** Use `ProviderFolderMapper` for multi-provider support.
/// This class now delegates to `ProviderFolderMapper` with `provider: .gmail`.
///
/// Spec ref: Email Sync spec FR-SYNC-01 step 1 (Folder discovery)
public enum GmailFolderMapper {

    /// Maps an IMAP folder's attributes and path to a `FolderType`.
    ///
    /// Delegates to `ProviderFolderMapper.folderType(imapPath:attributes:provider: .gmail)`.
    @available(*, deprecated, message: "Use ProviderFolderMapper.folderType(imapPath:attributes:provider:) instead")
    public static func folderType(
        imapPath: String,
        attributes: [String]
    ) -> FolderType {
        ProviderFolderMapper.folderType(imapPath: imapPath, attributes: attributes, provider: .gmail)
    }

    /// Determines whether a folder should be synced.
    ///
    /// Delegates to `ProviderFolderMapper.shouldSync(imapPath:attributes:provider: .gmail)`.
    @available(*, deprecated, message: "Use ProviderFolderMapper.shouldSync(imapPath:attributes:provider:) instead")
    public static func shouldSync(
        imapPath: String,
        attributes: [String]
    ) -> Bool {
        ProviderFolderMapper.shouldSync(imapPath: imapPath, attributes: attributes, provider: .gmail)
    }
}
