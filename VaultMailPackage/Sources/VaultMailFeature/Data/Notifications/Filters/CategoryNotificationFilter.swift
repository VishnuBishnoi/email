import Foundation

/// Filters notifications based on AI category preference.
///
/// If an email has no AI category or is uncategorized, it passes through (returns true).
/// Otherwise, the filter checks the per-category notification preference in SettingsStore.
///
/// Spec ref: NOTIF-09
@MainActor
public final class CategoryNotificationFilter: NotificationFilter {
    private let settingsStore: SettingsStore

    /// Creates a category notification filter.
    ///
    /// - Parameter settingsStore: The settings store providing per-category preferences.
    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    /// Returns `true` if the email should trigger a notification based on its category.
    ///
    /// - Parameter email: The email to evaluate.
    /// - Returns: `true` if the email's category is enabled or missing, `false` if disabled.
    public func shouldNotify(for email: Email) async -> Bool {
        // Pass through if no category or uncategorized
        guard let category = email.aiCategory, category != AICategory.uncategorized.rawValue else {
            return true
        }

        // Check settings for the category
        return settingsStore.notificationCategoryEnabled(for: category)
    }
}
