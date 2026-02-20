import Foundation

/// Stub filter for Focus Mode integration.
///
/// This filter is a placeholder for future Focus Mode support on iOS.
/// Currently, it always allows notifications. Integration with the
/// UIApplication.shared.connectedScenes Focus Mode detection will be
/// implemented in a future phase.
///
/// Spec ref: NOTIF-15
@MainActor
public final class FocusModeFilter: NotificationFilter {
    /// Initializes the filter.
    public init() {}

    /// Always returns `true`. Focus Mode integration is future work.
    public func shouldNotify(for email: Email) async -> Bool {
        true
    }
}
