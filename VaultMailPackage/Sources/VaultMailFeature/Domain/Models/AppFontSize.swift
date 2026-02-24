import Foundation
import SwiftUI

/// Global app font size preference.
public enum AppFontSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
    case extraLarge

    /// Human-readable label for picker UI.
    public var displayLabel: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    /// Scalar applied to theme typography tokens.
    public var scale: CGFloat {
        switch self {
        case .small: 0.6
        case .medium: 0.9
        case .large: 1.1
        case .extraLarge: 1.2
        }
    }

    /// Dynamic type size applied globally for text-style based fonts.
    public var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .xLarge
        case .extraLarge: .xxxLarge
        }
    }
}
