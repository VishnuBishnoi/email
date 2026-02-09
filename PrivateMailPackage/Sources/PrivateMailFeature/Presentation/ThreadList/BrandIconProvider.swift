import SwiftUI

/// Provides brand-specific avatar styling for well-known email senders.
///
/// Maps email domains to brand colors and display initials,
/// giving familiar senders recognizable avatars in the thread list.
/// For known brands, provides signature colors and initials as fallback.
/// For ALL domains, provides a favicon URL via Google's Favicon CDN
/// so ``AvatarView`` can display actual brand logo images.
///
/// Spec ref: Thread List visual enhancement
enum BrandIconProvider {

    // MARK: - Brand Info

    /// Brand information for avatar rendering.
    struct BrandInfo: Sendable, Equatable {
        /// The brand's signature color.
        let color: Color
        /// Single character or short initial to display.
        let initial: String
        /// The brand name (for accessibility).
        let name: String
    }

    // MARK: - Favicon Size

    /// Desired favicon size in points (will be fetched at 2× for Retina).
    private static let faviconSize = 128

    // MARK: - Lookup

    /// Look up brand info for an email address.
    /// Returns `nil` if the domain is not a recognized brand.
    static func brand(for email: String) -> BrandInfo? {
        guard let domain = extractDomain(from: email) else { return nil }
        return brandMap[domain]
    }

    /// Build a favicon URL for any email domain using Google's Favicon CDN.
    ///
    /// Works for ANY domain, not just recognized brands. Returns `nil`
    /// only if the email has no valid domain.
    ///
    /// - Parameter email: The sender's email address.
    /// - Returns: A URL to a high-res favicon image, or `nil`.
    static func faviconURL(for email: String) -> URL? {
        guard let domain = extractDomain(from: email) else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=\(faviconSize)")
    }

    // MARK: - Private

    /// Extract domain from email, normalized to lowercase.
    private static func extractDomain(from email: String) -> String? {
        guard let atIndex = email.lastIndex(of: "@") else { return nil }
        let domain = email[email.index(after: atIndex)...]
        let result = String(domain).lowercased()
        guard !result.isEmpty else { return nil }
        return result
    }

    // MARK: - Brand Map

    // swiftlint:disable line_length
    private static let brandMap: [String: BrandInfo] = [
        // Google
        "gmail.com":       BrandInfo(color: Color(red: 0.918, green: 0.263, blue: 0.208), initial: "G", name: "Google"),
        "google.com":      BrandInfo(color: Color(red: 0.918, green: 0.263, blue: 0.208), initial: "G", name: "Google"),
        "googlemail.com":  BrandInfo(color: Color(red: 0.918, green: 0.263, blue: 0.208), initial: "G", name: "Google"),

        // Microsoft
        "outlook.com":     BrandInfo(color: Color(red: 0.0, green: 0.471, blue: 0.843), initial: "M", name: "Microsoft"),
        "hotmail.com":     BrandInfo(color: Color(red: 0.0, green: 0.471, blue: 0.843), initial: "M", name: "Microsoft"),
        "live.com":        BrandInfo(color: Color(red: 0.0, green: 0.471, blue: 0.843), initial: "M", name: "Microsoft"),
        "microsoft.com":   BrandInfo(color: Color(red: 0.0, green: 0.471, blue: 0.843), initial: "M", name: "Microsoft"),

        // Apple
        "apple.com":       BrandInfo(color: Color(red: 0.392, green: 0.392, blue: 0.392), initial: "", name: "Apple"),
        "icloud.com":      BrandInfo(color: Color(red: 0.392, green: 0.392, blue: 0.392), initial: "", name: "Apple"),

        // Netflix
        "netflix.com":     BrandInfo(color: Color(red: 0.894, green: 0.071, blue: 0.071), initial: "N", name: "Netflix"),

        // Amazon
        "amazon.com":      BrandInfo(color: Color(red: 1.0, green: 0.596, blue: 0.0), initial: "a", name: "Amazon"),
        "amazon.co.uk":    BrandInfo(color: Color(red: 1.0, green: 0.596, blue: 0.0), initial: "a", name: "Amazon"),
        "amazon.in":       BrandInfo(color: Color(red: 1.0, green: 0.596, blue: 0.0), initial: "a", name: "Amazon"),

        // LinkedIn
        "linkedin.com":    BrandInfo(color: Color(red: 0.0, green: 0.467, blue: 0.706), initial: "in", name: "LinkedIn"),

        // Twitter / X
        "x.com":           BrandInfo(color: Color(red: 0.114, green: 0.114, blue: 0.114), initial: "X", name: "X"),
        "twitter.com":     BrandInfo(color: Color(red: 0.114, green: 0.114, blue: 0.114), initial: "X", name: "X"),

        // Facebook / Meta
        "facebook.com":    BrandInfo(color: Color(red: 0.059, green: 0.396, blue: 0.988), initial: "f", name: "Facebook"),
        "facebookmail.com": BrandInfo(color: Color(red: 0.059, green: 0.396, blue: 0.988), initial: "f", name: "Facebook"),
        "meta.com":        BrandInfo(color: Color(red: 0.059, green: 0.396, blue: 0.988), initial: "f", name: "Meta"),

        // GitHub
        "github.com":      BrandInfo(color: Color(red: 0.149, green: 0.161, blue: 0.176), initial: "GH", name: "GitHub"),

        // PayPal
        "paypal.com":      BrandInfo(color: Color(red: 0.0, green: 0.282, blue: 0.635), initial: "PP", name: "PayPal"),

        // Uber
        "uber.com":        BrandInfo(color: Color(red: 0.0, green: 0.0, blue: 0.0), initial: "U", name: "Uber"),

        // Airbnb
        "airbnb.com":      BrandInfo(color: Color(red: 1.0, green: 0.345, blue: 0.361), initial: "A", name: "Airbnb"),

        // Spotify
        "spotify.com":     BrandInfo(color: Color(red: 0.114, green: 0.725, blue: 0.329), initial: "S", name: "Spotify"),

        // Slack
        "slack.com":       BrandInfo(color: Color(red: 0.224, green: 0.059, blue: 0.322), initial: "S", name: "Slack"),

        // Dropbox
        "dropbox.com":     BrandInfo(color: Color(red: 0.0, green: 0.384, blue: 1.0), initial: "D", name: "Dropbox"),

        // Adobe
        "adobe.com":       BrandInfo(color: Color(red: 0.98, green: 0.0, blue: 0.0), initial: "A", name: "Adobe"),

        // Stripe
        "stripe.com":      BrandInfo(color: Color(red: 0.392, green: 0.322, blue: 0.945), initial: "S", name: "Stripe"),

        // OpenAI
        "openai.com":      BrandInfo(color: Color(red: 0.459, green: 0.655, blue: 0.541), initial: "AI", name: "OpenAI"),

        // YouTube
        "youtube.com":     BrandInfo(color: Color(red: 1.0, green: 0.0, blue: 0.0), initial: "YT", name: "YouTube"),

        // Instagram
        "instagram.com":   BrandInfo(color: Color(red: 0.867, green: 0.188, blue: 0.482), initial: "IG", name: "Instagram"),

        // WhatsApp
        "whatsapp.com":    BrandInfo(color: Color(red: 0.149, green: 0.847, blue: 0.396), initial: "W", name: "WhatsApp"),

        // Reddit
        "reddit.com":      BrandInfo(color: Color(red: 1.0, green: 0.275, blue: 0.0), initial: "R", name: "Reddit"),
        "redditmail.com":  BrandInfo(color: Color(red: 1.0, green: 0.275, blue: 0.0), initial: "R", name: "Reddit"),

        // Discord
        "discord.com":     BrandInfo(color: Color(red: 0.345, green: 0.396, blue: 0.949), initial: "D", name: "Discord"),

        // Notion
        "notion.so":       BrandInfo(color: Color(red: 0.149, green: 0.149, blue: 0.149), initial: "N", name: "Notion"),

        // Figma
        "figma.com":       BrandInfo(color: Color(red: 0.643, green: 0.318, blue: 0.996), initial: "F", name: "Figma"),

        // Vercel
        "vercel.com":      BrandInfo(color: Color(red: 0.0, green: 0.0, blue: 0.0), initial: "V", name: "Vercel"),

        // Shopify
        "shopify.com":     BrandInfo(color: Color(red: 0.588, green: 0.808, blue: 0.082), initial: "S", name: "Shopify"),

        // Zoom
        "zoom.us":         BrandInfo(color: Color(red: 0.169, green: 0.545, blue: 0.965), initial: "Z", name: "Zoom"),
    ]
    // swiftlint:enable line_length
}
