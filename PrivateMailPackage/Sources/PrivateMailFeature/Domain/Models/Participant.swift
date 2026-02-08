import Foundation

/// A decoded participant from Thread.participants JSON field.
///
/// Thread.participants is a JSON string: `[{"name":"John","email":"john@example.com"}]`
/// This struct provides type-safe parsing with graceful fallback on malformed data.
///
/// Spec ref: Thread List spec Section 5 (Data Model)
public struct Participant: Codable, Sendable, Equatable {
    /// Display name (may be nil if only email available)
    public let name: String?
    /// Email address (always present)
    public let email: String

    public init(name: String?, email: String) {
        self.name = name
        self.email = email
    }

    // MARK: - JSON Helpers

    /// Decode participants from a JSON string.
    /// Returns empty array for nil, empty, or malformed input.
    public static func decode(from jsonString: String?) -> [Participant] {
        guard let jsonString, !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8) else {
            return []
        }
        do {
            return try JSONDecoder().decode([Participant].self, from: data)
        } catch {
            return []
        }
    }

    /// Encode participants to a JSON string.
    public static func encode(_ participants: [Participant]) -> String {
        guard let data = try? JSONEncoder().encode(participants),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    /// Display name or email prefix as fallback.
    public var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return email.components(separatedBy: "@").first ?? email
    }
}
