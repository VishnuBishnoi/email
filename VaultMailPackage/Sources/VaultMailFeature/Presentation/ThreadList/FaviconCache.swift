import Foundation
import SwiftUI

/// Filesystem-backed favicon cache.
///
/// Downloads each domain's favicon at most once, persisting it to
/// `<Caches>/favicons/<domain>.png`. Subsequent requests are served
/// from disk instantly. An in-memory `NSCache` layer avoids repeated
/// file I/O for domains already loaded this session.
///
/// Uses an actor to guarantee thread-safe, non-reentrant downloads
/// (no duplicate requests for the same domain).
///
/// Spec ref: Thread List visual enhancement — brand icons
actor FaviconCache {

    // MARK: - Singleton

    /// Shared instance used by all ``CachedFaviconView`` instances.
    static let shared = FaviconCache()

    // MARK: - Storage

    /// In-memory LRU cache (domain → PlatformImage).
    private let memoryCache = NSCache<NSString, PlatformImage>()

    /// Active download tasks keyed by domain, preventing duplicate fetches.
    private var activeTasks: [String: Task<PlatformImage?, Never>] = [:]

    // MARK: - Init

    private init() {
        memoryCache.countLimit = 200
    }

    // MARK: - Public API

    /// Returns a cached favicon for the given domain, downloading if needed.
    ///
    /// - Parameter domain: The email domain (e.g. `"gmail.com"`).
    /// - Returns: A `PlatformImage` or `nil` if download failed.
    func favicon(for domain: String) async -> PlatformImage? {
        // 1. Check in-memory cache
        let key = domain as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // 2. Check filesystem cache
        let fileURL = cacheFileURL(for: domain)
        if let diskImage = loadFromDisk(at: fileURL) {
            memoryCache.setObject(diskImage, forKey: key)
            return diskImage
        }

        // 3. Coalesce concurrent requests for the same domain
        if let existing = activeTasks[domain] {
            return await existing.value
        }

        // 4. Download from Google Favicon CDN
        let task = Task<PlatformImage?, Never> {
            await downloadAndCache(domain: domain, to: fileURL)
        }
        activeTasks[domain] = task

        let result = await task.value
        activeTasks[domain] = nil

        if let image = result {
            memoryCache.setObject(image, forKey: key)
        }

        return result
    }

    /// Clears all cached favicons (memory + disk). Useful for testing.
    func clearAll() {
        memoryCache.removeAllObjects()
        let dir = cacheDirectory
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Filesystem Helpers

    /// `<Caches>/favicons/`
    private var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("favicons", isDirectory: true)
    }

    private func cacheFileURL(for domain: String) -> URL {
        let sanitized = domain
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return cacheDirectory.appendingPathComponent("\(sanitized).png")
    }

    private func loadFromDisk(at url: URL) -> PlatformImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return PlatformImage(data: data)
    }

    private func saveToDisk(_ data: Data, at url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Network

    private func downloadAndCache(domain: String, to fileURL: URL) async -> PlatformImage? {
        guard let url = URL(
            string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128"
        ) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  !data.isEmpty else {
                return nil
            }

            // Validate it's actually a decodable image
            guard let image = PlatformImage(data: data) else { return nil }

            // Google returns a generic globe icon (16×16) for unknown domains.
            // Only cache if the image is reasonably sized (> 16px).
            guard max(image.size.width, image.size.height) > 16 else { return nil }

            saveToDisk(data, at: fileURL)
            return image
        } catch {
            return nil
        }
    }
}
