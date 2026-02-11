import Testing
import SwiftUI
@testable import VaultMailFeature

@Suite("BrandIconProvider")
struct BrandIconProviderTests {

    @Test("Known Google domain returns Google brand info")
    func googleBrand() {
        let brand = BrandIconProvider.brand(for: "notifications@google.com")
        #expect(brand != nil)
        #expect(brand?.name == "Google")
        #expect(brand?.initial == "G")
    }

    @Test("Gmail domain maps to Google brand")
    func gmailDomain() {
        let brand = BrandIconProvider.brand(for: "user@gmail.com")
        #expect(brand?.name == "Google")
        #expect(brand?.initial == "G")
    }

    @Test("GitHub domain returns correct brand info")
    func githubBrand() {
        let brand = BrandIconProvider.brand(for: "noreply@github.com")
        #expect(brand?.name == "GitHub")
        #expect(brand?.initial == "GH")
    }

    @Test("Netflix domain returns correct brand info")
    func netflixBrand() {
        let brand = BrandIconProvider.brand(for: "info@netflix.com")
        #expect(brand?.name == "Netflix")
        #expect(brand?.initial == "N")
    }

    @Test("Unknown domain returns nil")
    func unknownDomain() {
        let brand = BrandIconProvider.brand(for: "user@randomcompany.io")
        #expect(brand == nil)
    }

    @Test("Email without @ returns nil")
    func noAtSymbol() {
        let brand = BrandIconProvider.brand(for: "localhost")
        #expect(brand == nil)
    }

    @Test("Empty email returns nil")
    func emptyEmail() {
        let brand = BrandIconProvider.brand(for: "")
        #expect(brand == nil)
    }

    @Test("Case insensitive domain matching")
    func caseInsensitive() {
        let brand = BrandIconProvider.brand(for: "User@GMAIL.COM")
        #expect(brand?.name == "Google")
    }

    @Test("All Microsoft domains map to Microsoft")
    func microsoftDomains() {
        let domains = ["outlook.com", "hotmail.com", "live.com", "microsoft.com"]
        for domain in domains {
            let brand = BrandIconProvider.brand(for: "test@\(domain)")
            #expect(brand?.name == "Microsoft", "Expected Microsoft for \(domain)")
            #expect(brand?.initial == "M")
        }
    }

    @Test("Amazon regional domains map to Amazon")
    func amazonRegionalDomains() {
        let brand1 = BrandIconProvider.brand(for: "orders@amazon.com")
        let brand2 = BrandIconProvider.brand(for: "orders@amazon.in")
        #expect(brand1?.name == "Amazon")
        #expect(brand2?.name == "Amazon")
    }

    @Test("All mapped brands have non-empty initial and name")
    func allBrandsValid() {
        let testDomains = [
            "gmail.com", "netflix.com", "amazon.com", "linkedin.com",
            "github.com", "paypal.com", "spotify.com", "discord.com",
            "openai.com", "zoom.us", "notion.so", "figma.com",
        ]
        for domain in testDomains {
            let brand = BrandIconProvider.brand(for: "test@\(domain)")
            #expect(brand != nil, "Expected brand for \(domain)")
            #expect(!brand!.initial.isEmpty, "Expected non-empty initial for \(domain)")
            #expect(!brand!.name.isEmpty, "Expected non-empty name for \(domain)")
        }
    }

    // MARK: - Favicon URL Tests

    @Test("Favicon URL generated for known brand domain")
    func faviconURLKnownBrand() {
        let url = BrandIconProvider.faviconURL(for: "user@gmail.com")
        #expect(url != nil)
        #expect(url?.absoluteString.contains("domain=gmail.com") == true)
        #expect(url?.absoluteString.contains("sz=128") == true)
    }

    @Test("Favicon URL generated for unknown domain")
    func faviconURLUnknownDomain() {
        let url = BrandIconProvider.faviconURL(for: "user@randomstartup.io")
        #expect(url != nil)
        #expect(url?.absoluteString.contains("domain=randomstartup.io") == true)
    }

    @Test("Favicon URL nil for empty email")
    func faviconURLEmptyEmail() {
        let url = BrandIconProvider.faviconURL(for: "")
        #expect(url == nil)
    }

    @Test("Favicon URL nil for email without @")
    func faviconURLNoAt() {
        let url = BrandIconProvider.faviconURL(for: "localhost")
        #expect(url == nil)
    }

    @Test("Favicon URL uses lowercase domain")
    func faviconURLLowercase() {
        let url = BrandIconProvider.faviconURL(for: "User@GOOGLE.COM")
        #expect(url?.absoluteString.contains("domain=google.com") == true)
    }

    @Test("Favicon URL uses Google Favicon CDN base")
    func faviconURLBase() {
        let url = BrandIconProvider.faviconURL(for: "test@example.com")
        #expect(url?.absoluteString.hasPrefix("https://www.google.com/s2/favicons") == true)
    }
}
