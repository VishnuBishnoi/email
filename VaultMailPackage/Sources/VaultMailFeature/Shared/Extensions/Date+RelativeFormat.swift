import Foundation

/// Relative timestamp formatting for thread row display.
///
/// Format rules per Thread List spec FR-TL-01:
/// - Today: "3:42 PM" (time only)
/// - Yesterday: "Yesterday"
/// - This week (2-6 days ago): "Tue" (abbreviated weekday)
/// - This year (older than this week): "Jan 15" (month + day)
/// - Older years: "Jan 15, 2024" (abbreviated month, day, full year)
///
/// Spec ref: Thread List spec FR-TL-01 (Timestamp)
extension Date {
    /// Format this date as a relative timestamp for thread row display.
    /// - Parameter now: The reference "current" date (defaults to Date.now, injectable for testing)
    /// - Returns: Formatted string per spec rules
    public func relativeThreadFormat(relativeTo now: Date = .now) -> String {
        let calendar = Calendar.current

        // Today: show time only
        if calendar.isDate(self, inSameDayAs: now) {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: self)
        }

        // Yesterday
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(self, inSameDayAs: yesterday) {
            return "Yesterday"
        }

        // This week (within last 7 days, but not today or yesterday)
        let startOfToday = calendar.startOfDay(for: now)
        if let sixDaysAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday),
           self >= sixDaysAgo {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: self)
        }

        // This year
        if calendar.component(.year, from: self) == calendar.component(.year, from: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: self)
        }

        // Older years: readable date with abbreviated month
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: self)
    }
}
