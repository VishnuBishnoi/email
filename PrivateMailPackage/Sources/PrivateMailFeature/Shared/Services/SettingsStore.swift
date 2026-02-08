import Foundation
import SwiftUI

/// UserDefaults-backed observable settings store.
///
/// All app-wide preferences are stored in UserDefaults per spec Section 5 storage
/// strategy. Per-account settings (syncWindowDays, displayName) live on the
/// Account SwiftData entity and are managed via ManageAccountsUseCase.
///
/// Properties use `didSet` to write back to UserDefaults immediately,
/// satisfying NFR-SET-04 (< 100ms save latency).
///
/// Spec ref: Settings & Onboarding spec Section 5, FR-SET-01
@Observable
@MainActor
public final class SettingsStore {

    private let defaults: UserDefaults

    // MARK: - Appearance

    /// App theme (System/Light/Dark). Changes apply immediately via preferredColorScheme.
    /// Spec ref: FR-SET-01 Appearance section
    public var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    /// Computed color scheme for SwiftUI's preferredColorScheme modifier.
    public var colorScheme: ColorScheme? {
        switch theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Category tab visibility toggles. Keyed by AICategory rawValue.
    /// All on by default (Primary, Social, Promotions, Updates).
    /// Spec ref: FR-SET-01 Appearance section, Thread List FR-TL-02
    public var categoryTabVisibility: [String: Bool] {
        didSet { defaults.setJSON(categoryTabVisibility, forKey: Keys.categoryTabVisibility) }
    }

    // MARK: - Composition

    /// Undo send delay. Change applies to the next send.
    /// Spec ref: FR-SET-01 Composition section, Email Composer FR-COMP-02
    public var undoSendDelay: UndoSendDelay {
        didSet { defaults.set(undoSendDelay.rawValue, forKey: Keys.undoSendDelay) }
    }

    /// Default sending account ID. Hidden if only one account exists.
    /// Spec ref: FR-SET-01 Composition section, FR-ACCT-02
    public var defaultSendingAccountId: String? {
        didSet { defaults.set(defaultSendingAccountId, forKey: Keys.defaultSendingAccountId) }
    }

    // MARK: - Security

    /// App lock enabled. Requires biometric/passcode on cold launch and background return.
    /// Spec ref: FR-SET-01 Security section, Foundation Section 9.2
    public var appLockEnabled: Bool {
        didSet { defaults.set(appLockEnabled, forKey: Keys.appLockEnabled) }
    }

    // MARK: - Notifications

    /// Per-account notification preferences. Keyed by account ID. Default: true for new accounts.
    /// Spec ref: FR-SET-01 Notifications section
    public var notificationPreferences: [String: Bool] {
        didSet { defaults.setJSON(notificationPreferences, forKey: Keys.notificationPreferences) }
    }

    // MARK: - Data Management

    /// Per-account attachment cache limits in MB. Keyed by account ID. Default: 500 MB.
    /// LRU eviction when exceeded (Foundation Section 8.1).
    /// Spec ref: FR-SET-03
    public var attachmentCacheLimits: [String: Int] {
        didSet { defaults.setJSON(attachmentCacheLimits, forKey: Keys.attachmentCacheLimits) }
    }

    // MARK: - Onboarding

    /// Whether onboarding has been completed. Persisted to prevent re-display.
    /// Reset when all accounts are removed or data is wiped.
    /// Spec ref: FR-OB-01 post-onboarding
    public var isOnboardingComplete: Bool {
        didSet { defaults.set(isOnboardingComplete, forKey: Keys.isOnboardingComplete) }
    }

    // MARK: - Init

    /// Creates a SettingsStore reading from the given UserDefaults.
    /// - Parameter defaults: UserDefaults instance. Use `UserDefaults(suiteName:)` for tests.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Read initial values from UserDefaults, falling back to spec defaults
        self.theme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        if defaults.object(forKey: Keys.undoSendDelay) != nil {
            self.undoSendDelay = UndoSendDelay(rawValue: defaults.integer(forKey: Keys.undoSendDelay)) ?? .fiveSeconds
        } else {
            self.undoSendDelay = .fiveSeconds
        }
        self.categoryTabVisibility = defaults.json(forKey: Keys.categoryTabVisibility) ?? Self.defaultCategoryVisibility
        self.appLockEnabled = defaults.bool(forKey: Keys.appLockEnabled)
        self.notificationPreferences = defaults.json(forKey: Keys.notificationPreferences) ?? [:]
        self.attachmentCacheLimits = defaults.json(forKey: Keys.attachmentCacheLimits) ?? [:]
        self.isOnboardingComplete = defaults.bool(forKey: Keys.isOnboardingComplete)
        self.defaultSendingAccountId = defaults.string(forKey: Keys.defaultSendingAccountId)
    }

    // MARK: - Helpers

    /// Returns the attachment cache limit for a given account (default 500 MB).
    public func cacheLimit(for accountId: String) -> Int {
        attachmentCacheLimits[accountId] ?? AppConstants.maxAttachmentCacheMB
    }

    /// Sets the attachment cache limit for a given account.
    public func setCacheLimit(_ limitMB: Int, for accountId: String) {
        attachmentCacheLimits[accountId] = limitMB
    }

    /// Returns whether notifications are enabled for a given account (default true).
    public func notificationsEnabled(for accountId: String) -> Bool {
        notificationPreferences[accountId] ?? true
    }

    /// Resets all settings to defaults. Used by "Wipe All Data".
    /// Spec ref: FR-SET-03, Foundation Section 9.3
    public func resetAll() {
        theme = .system
        undoSendDelay = .fiveSeconds
        categoryTabVisibility = Self.defaultCategoryVisibility
        appLockEnabled = false
        notificationPreferences = [:]
        attachmentCacheLimits = [:]
        isOnboardingComplete = false
        defaultSendingAccountId = nil
    }

    // MARK: - Constants

    /// Default category visibility: all togglable categories enabled.
    /// Only Primary, Social, Promotions, Updates are togglable (spec FR-SET-01).
    static let defaultCategoryVisibility: [String: Bool] = [
        AICategory.primary.rawValue: true,
        AICategory.social.rawValue: true,
        AICategory.promotions.rawValue: true,
        AICategory.updates.rawValue: true,
    ]

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let theme = "appTheme"
        static let undoSendDelay = "undoSendDelaySeconds"
        static let categoryTabVisibility = "categoryTabVisibility"
        static let appLockEnabled = "appLockEnabled"
        static let notificationPreferences = "notificationPreferences"
        static let attachmentCacheLimits = "attachmentCacheLimits"
        static let isOnboardingComplete = "isOnboardingComplete"
        static let defaultSendingAccountId = "defaultSendingAccountId"
    }
}

// MARK: - UserDefaults JSON Helpers

private extension UserDefaults {
    func setJSON<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            set(data, forKey: key)
        }
    }

    func json<T: Decodable>(forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
