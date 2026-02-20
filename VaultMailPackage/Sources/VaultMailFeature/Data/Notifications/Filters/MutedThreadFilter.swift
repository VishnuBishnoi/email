import Foundation

/// Filters out notifications for threads that the user has muted.
///
/// A muted thread never triggers notifications, regardless of other filter settings.
/// Users can toggle mute state via SettingsStore.toggleMuteThread(_:).
///
/// Spec ref: NOTIF-11
@MainActor
public final class MutedThreadFilter: NotificationFilter {
    private let settingsStore: SettingsStore

    /// Initializes the filter with a settings store.
    /// - Parameter settingsStore: The settings store containing muted thread IDs.
    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    /// Returns `false` if the email's thread is muted, `true` otherwise.
    public func shouldNotify(for email: Email) async -> Bool {
        !settingsStore.mutedThreadIds.contains(email.threadId)
    }
}
