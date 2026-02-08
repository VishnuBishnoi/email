import Testing
import Foundation
@testable import PrivateMailFeature

@Suite("Date Relative Format Tests")
struct DateRelativeFormatTests {
    // Use a fixed "now" for deterministic tests: Feb 8, 2026 at 2:00 PM
    let now: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 8
        components.hour = 14
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)!
    }()

    @Test("Today shows time only")
    func todayShowsTime() {
        // Same day at 3:42 PM
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 8
        components.hour = 15
        components.minute = 42
        let date = Calendar.current.date(from: components)!
        let result = date.relativeThreadFormat(relativeTo: now)
        // Should contain time format like "3:42 PM"
        #expect(result.contains("3:42"))
    }

    @Test("Today early morning shows time only")
    func todayEarlyMorning() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 8
        components.hour = 6
        components.minute = 0
        let date = Calendar.current.date(from: components)!
        let result = date.relativeThreadFormat(relativeTo: now)
        #expect(result.contains("6:00"))
    }

    @Test("Yesterday shows 'Yesterday'")
    func yesterdayShowsYesterday() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 7
        components.hour = 10
        components.minute = 30
        let date = Calendar.current.date(from: components)!
        let result = date.relativeThreadFormat(relativeTo: now)
        #expect(result == "Yesterday")
    }

    @Test("This week shows abbreviated weekday")
    func thisWeekShowsWeekday() {
        // 3 days ago = Feb 5, 2026 (Thursday)
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 5
        components.hour = 9
        components.minute = 0
        let date = Calendar.current.date(from: components)!
        let result = date.relativeThreadFormat(relativeTo: now)
        #expect(result == "Thu")
    }

    @Test("6 days ago still shows weekday")
    func sixDaysAgoShowsWeekday() {
        // 6 days ago = Feb 2, 2026 (Monday)
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 2
        components.hour = 12
        components.minute = 0
        let date = Calendar.current.date(from: components)!
        let result = date.relativeThreadFormat(relativeTo: now)
        #expect(result == "Mon")
    }

    @Test("This year shows month and day")
    func thisYearShowsMonthDay() {
        // Jan 15, 2026
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = 12
        components.minute = 0
        let date = Calendar.current.date(from: components)!
        let result = date.relativeThreadFormat(relativeTo: now)
        #expect(result == "Jan 15")
    }

    @Test("Older year shows numeric date")
    func olderYearShowsNumericDate() {
        // Feb 5, 2025
        var components = DateComponents()
        components.year = 2025
        components.month = 2
        components.day = 5
        components.hour = 12
        components.minute = 0
        let date = Calendar.current.date(from: components)!
        let result = date.relativeThreadFormat(relativeTo: now)
        #expect(result == "Feb 5, 2025")
    }

    @Test("Midnight edge case still shows today format")
    func midnightEdgeCase() {
        // Midnight of the same day
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 8
        components.hour = 0
        components.minute = 0
        components.second = 0
        let date = Calendar.current.date(from: components)!
        let result = date.relativeThreadFormat(relativeTo: now)
        #expect(result.contains("12:00"))
    }

    @Test("Year boundary: Dec 31 last year shows numeric date")
    func yearBoundary() {
        // Dec 31, 2025
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 31
        components.hour = 23
        components.minute = 59
        let date = Calendar.current.date(from: components)!
        let result = date.relativeThreadFormat(relativeTo: now)
        #expect(result == "Dec 31, 2025")
    }

    @Test("Jan 1 this year shows month day")
    func janFirstThisYear() {
        // Jan 1, 2026
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = 0
        components.minute = 0
        let date = Calendar.current.date(from: components)!
        let result = date.relativeThreadFormat(relativeTo: now)
        #expect(result == "Jan 1")
    }

    @Test("7 days ago shows month and day, not weekday")
    func sevenDaysAgoShowsMonthDay() {
        // Feb 1, 2026 = 7 days before Feb 8
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 1
        components.hour = 12
        components.minute = 0
        let date = Calendar.current.date(from: components)!
        let result = date.relativeThreadFormat(relativeTo: now)
        #expect(result == "Feb 1")
    }

    @Test("Future date in same year falls into weekday branch")
    func futureDateThisYear() {
        // Note: The current implementation treats future dates that are >= sixDaysAgo
        // as "this week", showing the abbreviated weekday. Mar 15, 2026 is a Sunday.
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 10
        components.minute = 0
        let date = Calendar.current.date(from: components)!
        let result = date.relativeThreadFormat(relativeTo: now)
        // Future dates >= sixDaysAgo currently fall into the weekday branch
        #expect(result == "Sun")
    }
}
