import Foundation

/// Filters out notifications during configured quiet hours.
///
/// When quiet hours are enabled, notifications are suppressed within the
/// configured time window. The filter handles both same-day ranges (e.g., 22:00-23:00)
/// and overnight ranges (e.g., 22:00-07:00).
///
/// Spec ref: NOTIF-14
@MainActor
public final class QuietHoursFilter: NotificationFilter {
    private let settingsStore: SettingsStore

    /// Initializes the filter with a settings store.
    /// - Parameter settingsStore: The settings store containing quiet hours configuration.
    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    /// Returns `false` if quiet hours are enabled and current time is within the quiet window, `true` otherwise.
    public func shouldNotify(for email: Email) async -> Bool {
        // If quiet hours are disabled, always allow notifications
        if !settingsStore.quietHoursEnabled {
            return true
        }

        // Calculate current time in minutes since midnight
        let dateComponents = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let currentMinutes = (dateComponents.hour ?? 0) * 60 + (dateComponents.minute ?? 0)

        let start = settingsStore.quietHoursStart
        let end = settingsStore.quietHoursEnd

        // Check if current time falls within the quiet hours window
        if start <= end {
            // Normal range (e.g., 09:00-17:00 same day)
            return !(currentMinutes >= start && currentMinutes < end)
        } else {
            // Overnight range (e.g., 22:00-07:00)
            return !(currentMinutes >= start || currentMinutes < end)
        }
    }
}
