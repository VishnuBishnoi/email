import Foundation

/// Checks if notifications are enabled for the email's account via O(1) SettingsStore lookup.
/// Spec ref: NOTIF-09
@MainActor
public final class AccountNotificationFilter: NotificationFilter {

    private let settingsStore: SettingsStore

    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    public func shouldNotify(for email: Email) async -> Bool {
        settingsStore.notificationsEnabled(for: email.accountId)
    }
}
