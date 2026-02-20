import Foundation

/// Orchestrates the notification filter chain with VIP override logic.
///
/// - Spec ref: NOTIF-07
@MainActor
public final class NotificationFilterPipeline {
    private let vipFilter: VIPContactFilter
    private let filters: [any NotificationFilter]

    public init(vipFilter: VIPContactFilter, filters: [any NotificationFilter]) {
        self.vipFilter = vipFilter
        self.filters = filters
    }

    /// Determines whether a notification should be sent for an email.
    ///
    /// First checks VIP status: if the email is from a VIP contact, always notifies.
    /// Then evaluates all filters with AND logic and early termination.
    ///
    /// - Parameter email: The email to evaluate.
    /// - Returns: True if the notification should be sent, false otherwise.
    public func shouldNotify(for email: Email) async -> Bool {
        // VIP override: if email is from VIP, always notify
        if (await vipFilter.shouldNotify(for: email)) {
            return true
        }

        // Evaluate all filters with AND logic and early termination
        for filter in filters {
            if (!(await filter.shouldNotify(for: email))) {
                return false
            }
        }

        return true
    }

    // MARK: - Debug Diagnostics

    #if DEBUG
    /// Runs the filter pipeline and returns a human-readable diagnostic string.
    ///
    /// Useful for debugging notification delivery in the settings UI.
    /// Reports which filter blocked the email, or confirms it passed all filters.
    public func diagnose(for email: Email) async -> String {
        if await vipFilter.shouldNotify(for: email) {
            return "VIP override — notification will always be sent"
        }

        for (index, filter) in filters.enumerated() {
            if !(await filter.shouldNotify(for: email)) {
                let filterName = String(describing: type(of: filter))
                return "Blocked by \(filterName) (filter \(index + 1)/\(filters.count))"
            }
        }

        return "Passed all \(filters.count) filters"
    }
    #endif
}
