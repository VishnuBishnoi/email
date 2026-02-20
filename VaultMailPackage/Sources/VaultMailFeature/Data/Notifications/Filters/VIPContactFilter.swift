import Foundation

/// Filters notifications based on VIP contact status.
///
/// Returns `true` if the email sender is in the VIP contacts list (case-insensitive).
/// VIP contacts are checked against a lowercased set stored in SettingsStore.
///
/// Note: VIPContactFilter is used as both a regular filter in the pipeline and as a special
/// override mechanism. When used as an override, if a sender is VIP, the email always
/// triggers a notification regardless of other filter settings. The filter itself just
/// checks membership in the VIP contacts list.
///
/// Spec ref: NOTIF-10
@MainActor
public final class VIPContactFilter: NotificationFilter {
    private let settingsStore: SettingsStore

    /// Creates a VIP contact notification filter.
    ///
    /// - Parameter settingsStore: The settings store providing the VIP contacts list.
    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    /// Returns `true` if the email sender is a VIP contact.
    ///
    /// - Parameter email: The email to evaluate.
    /// - Returns: `true` if the sender is in the VIP contacts list, `false` otherwise.
    public func shouldNotify(for email: Email) async -> Bool {
        settingsStore.vipContacts.contains(email.fromAddress.lowercased())
    }
}
