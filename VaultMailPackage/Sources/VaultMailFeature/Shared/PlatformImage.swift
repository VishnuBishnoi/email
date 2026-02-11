import SwiftUI

// MARK: - Cross-Platform Image Type

#if canImport(UIKit)
import UIKit

/// Platform-native image type: `UIImage` on iOS/tvOS, `NSImage` on macOS.
///
/// Both types share `init?(data:)` and `var size: CGSize`, making them
/// interchangeable for the favicon cache and any future image utilities.
typealias PlatformImage = UIImage

#elseif canImport(AppKit)
import AppKit

/// Platform-native image type: `UIImage` on iOS/tvOS, `NSImage` on macOS.
typealias PlatformImage = NSImage
#endif

// MARK: - SwiftUI Bridge

extension Image {
    /// Creates a SwiftUI `Image` from a platform-native image type.
    ///
    /// Bridges `UIImage` on iOS and `NSImage` on macOS into SwiftUI's
    /// unified `Image` type, keeping consumer code platform-agnostic.
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}
