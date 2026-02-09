import SwiftUI

/// Displays a sender's favicon fetched via ``FaviconCache``, with a
/// colored-circle + initials fallback.
///
/// **Rendering logic:**
/// - While loading → colored circle with initials (placeholder).
/// - Favicon loaded → the favicon image fills the circle on a white
///   background (no brand color bleed-through).
/// - Favicon failed → colored circle with initials (permanent fallback).
///
/// Uses `.task(id:)` tied to the email so the image reloads if the
/// participant changes. Images are cached to the filesystem by
/// ``FaviconCache`` so each domain is downloaded at most once.
///
/// Spec ref: Thread List visual enhancement — brand icons
struct CachedFaviconView: View {

    let email: String
    let diameter: CGFloat
    let fallbackColor: Color
    let initials: String
    let initialsFontSize: CGFloat?

    @State private var faviconImage: PlatformImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let faviconImage {
                Image(platformImage: faviconImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                    .transition(.opacity)
            } else {
                Circle()
                    .fill(fallbackColor)
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        Text(initials)
                            .font(
                                initialsFontSize.map { .system(size: $0) } ?? .caption
                            )
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .task(id: email) {
            await loadFavicon()
        }
    }

    private func loadFavicon() async {
        guard !email.isEmpty else { return }

        guard let domain = extractDomain(from: email) else {
            didFail = true
            return
        }

        if let image = await FaviconCache.shared.favicon(for: domain) {
            withAnimation(.easeIn(duration: 0.15)) {
                faviconImage = image
            }
        } else {
            didFail = true
        }
    }

    /// Extract domain from email, normalized to lowercase.
    private func extractDomain(from email: String) -> String? {
        guard let atIndex = email.lastIndex(of: "@") else { return nil }
        let domain = email[email.index(after: atIndex)...]
        let result = String(domain).lowercased()
        guard !result.isEmpty else { return nil }
        return result
    }
}

// MARK: - Previews

#Preview("Google Favicon") {
    CachedFaviconView(
        email: "test@google.com",
        diameter: 40,
        fallbackColor: .red,
        initials: "G",
        initialsFontSize: nil
    )
    .padding()
}

#Preview("Unknown Domain") {
    CachedFaviconView(
        email: "user@randomstartup.xyz",
        diameter: 40,
        fallbackColor: .purple,
        initials: "RS",
        initialsFontSize: nil
    )
    .padding()
}
