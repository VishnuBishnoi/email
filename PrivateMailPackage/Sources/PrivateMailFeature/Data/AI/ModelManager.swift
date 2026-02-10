import Foundation
import CryptoKit

/// Manages GGUF model downloads, verification, storage, and lifecycle.
///
/// Responsible for:
/// - Listing available models with metadata (name, size, license, download status)
/// - Downloading GGUF files via HTTPS with progress reporting
/// - Resumable downloads (HTTP Range requests)
/// - SHA-256 integrity verification post-download
/// - Deleting models and reporting storage usage
///
/// All models are stored in the app's Application Support directory
/// under `Models/`.
///
/// Spec ref: FR-AI-01 (Spec Section 9), AC-A-03
public actor ModelManager {

    // MARK: - Model Definitions

    /// Metadata for a downloadable AI model.
    public struct ModelInfo: Sendable, Identifiable {
        public let id: String
        public let name: String
        public let fileName: String
        public let downloadURL: URL
        public let size: UInt64          // Expected file size in bytes
        public let sha256: String        // Expected SHA-256 hex digest
        public let license: String
        public let minRAMGB: Int         // Minimum device RAM in GB

        /// Human-readable file size (e.g., "1.0 GB").
        public var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
    }

    /// Download status for a model.
    public enum DownloadStatus: Sendable, Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case verifying
        case failed(String)
    }

    /// Combined model info with its current status.
    public struct ModelState: Sendable, Identifiable {
        public let info: ModelInfo
        public var status: DownloadStatus

        public var id: String { info.id }
    }

    // MARK: - Available Models

    /// Registry of supported models.
    ///
    /// Spec ref: AI spec Section 3 (Model Selection)
    /// - Qwen3-1.7B-Instruct (Q4_K_M): Primary model for devices with ≥ 6 GB RAM
    /// - Qwen3-0.6B (Q4_K_M): Fallback for devices with < 6 GB RAM
    public static let availableModelInfos: [ModelInfo] = [
        ModelInfo(
            id: "qwen3-1.7b-q4km",
            name: "Qwen3 1.7B Instruct",
            fileName: "Qwen3-1.7B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf")!,
            size: 1_107_409_472,   // ~1.11 GB (exact from HuggingFace LFS)
            sha256: "b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897",
            license: "Apache 2.0",
            minRAMGB: 6
        ),
        ModelInfo(
            id: "qwen3-0.6b-q4km",
            name: "Qwen3 0.6B",
            fileName: "Qwen3-0.6B-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf")!,
            size: 396_705_472,     // ~397 MB (exact from HuggingFace LFS)
            sha256: "ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a",
            license: "Apache 2.0",
            minRAMGB: 4
        ),
    ]

    // MARK: - State

    private var downloadStatuses: [String: DownloadStatus] = [:]
    /// Active download tasks keyed by model ID (for cancellation).
    private var activeDownloadTasks: [String: Task<Void, any Error>] = [:]
    private let modelsDirectory: URL
    private let fileManager = FileManager.default
    private let urlSession: URLSession

    /// Buffer size for chunked file writes during download (256 KB).
    private static let downloadBufferSize = 256 * 1024

    // MARK: - Init

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession

        // Store models in Application Support/Models/
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modelsDirectory = appSupport.appendingPathComponent("Models", isDirectory: true)

        // Create directory if needed
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    /// Initialize with a custom directory (for testing).
    public init(modelsDirectory: URL, urlSession: URLSession = .shared) {
        self.modelsDirectory = modelsDirectory
        self.urlSession = urlSession
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// List all available models with their current download status.
    ///
    /// Spec ref: AC-A-03 — `availableModels()` MUST list models with name, size, license, and download status.
    public func availableModels() -> [ModelState] {
        Self.availableModelInfos.map { info in
            let status = currentStatus(for: info)
            return ModelState(info: info, status: status)
        }
    }

    /// Download a model by ID with progress reporting.
    ///
    /// - Parameters:
    ///   - id: The model identifier.
    ///   - progress: Async stream callback reporting progress 0.0–1.0.
    /// - Throws: `AIEngineError.downloadFailed` or `AIEngineError.downloadCancelled`.
    ///
    /// Spec ref: AC-A-03 — `downloadModel(id:)` MUST download via HTTPS with progress (0-100%).
    public func downloadModel(
        id: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let info = Self.availableModelInfos.first(where: { $0.id == id }) else {
            throw AIEngineError.modelNotFound(path: id)
        }

        let destination = modelPath(for: info)

        // If already downloaded and valid, skip
        if fileManager.fileExists(atPath: destination.path) {
            if info.sha256.isEmpty || (try? verifyIntegrity(path: destination, sha256: info.sha256)) != nil {
                downloadStatuses[id] = .downloaded
                progress(1.0)
                return
            }
            // Corrupt file — delete and re-download
            try? fileManager.removeItem(at: destination)
        }

        downloadStatuses[id] = .downloading(progress: 0.0)

        // Wrap download in a tracked Task for cancellation support (P0-5)
        let downloadTask = Task { [self] in
            try await self.performDownload(info: info, destination: destination, progress: progress)
        }
        activeDownloadTasks[id] = downloadTask

        do {
            try await downloadTask.value
            activeDownloadTasks[id] = nil
        } catch {
            activeDownloadTasks[id] = nil
            throw error
        }
    }

    /// Internal download implementation — runs inside a tracked Task for cancellation.
    private func performDownload(
        info: ModelInfo,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let id = info.id

        // Check for partial download to resume
        let partialPath = destination.appendingPathExtension("partial")
        var request = URLRequest(url: info.downloadURL)

        var existingBytes: Int64 = 0
        if let attrs = try? fileManager.attributesOfItem(atPath: partialPath.path),
           let fileSize = attrs[.size] as? Int64, fileSize > 0 {
            existingBytes = fileSize
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
        }

        do {
            let (asyncBytes, response) = try await urlSession.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw AIEngineError.downloadFailed(
                    NSError(domain: "ModelManager", code: statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"])
                )
            }

            // If server returned 200 (full file) instead of 206 (partial),
            // the Range header was ignored — truncate partial file to avoid
            // appending the full content onto existing bytes (corruption).
            let isResumed = httpResponse.statusCode == 206
            if existingBytes > 0 && !isResumed {
                try? fileManager.removeItem(at: partialPath)
                existingBytes = 0
            }

            let totalBytes = (httpResponse.expectedContentLength > 0)
                ? httpResponse.expectedContentLength + existingBytes
                : Int64(info.size)

            // Open file for writing (append if resuming)
            if !fileManager.fileExists(atPath: partialPath.path) {
                fileManager.createFile(atPath: partialPath.path, contents: nil)
            }
            let fileHandle = try FileHandle(forWritingTo: partialPath)
            if isResumed && existingBytes > 0 {
                fileHandle.seekToEndOfFile()
            }

            var downloadedBytes = existingBytes
            let reportInterval: Int64 = max(totalBytes / 200, 65_536)
            var lastReportedBytes: Int64 = 0

            // Buffer writes in chunks (P0-2: avoid byte-by-byte writes)
            var buffer = Data()
            buffer.reserveCapacity(Self.downloadBufferSize)

            for try await byte in asyncBytes {
                guard !Task.isCancelled else {
                    fileHandle.closeFile()
                    downloadStatuses[id] = .notDownloaded
                    throw AIEngineError.downloadCancelled
                }

                buffer.append(byte)
                downloadedBytes += 1

                // Flush buffer when full
                if buffer.count >= Self.downloadBufferSize {
                    fileHandle.write(buffer)
                    buffer.removeAll(keepingCapacity: true)
                }

                if downloadedBytes - lastReportedBytes >= reportInterval {
                    let pct = Double(downloadedBytes) / Double(totalBytes)
                    downloadStatuses[id] = .downloading(progress: pct)
                    progress(pct)
                    lastReportedBytes = downloadedBytes
                }
            }

            // Flush remaining bytes
            if !buffer.isEmpty {
                fileHandle.write(buffer)
            }

            fileHandle.closeFile()

            // Move partial to final
            try fileManager.moveItem(at: partialPath, to: destination)

            // Verify integrity (P0-3: warn when checksums are empty)
            downloadStatuses[id] = .verifying
            if info.sha256.isEmpty {
                #if DEBUG
                print("[ModelManager] ⚠️ No SHA-256 checksum for \(info.id) — skipping integrity verification. Fill checksums before release.")
                #endif
            } else {
                try verifyIntegrity(path: destination, sha256: info.sha256)
            }

            downloadStatuses[id] = .downloaded
            progress(1.0)

        } catch let error as AIEngineError {
            downloadStatuses[id] = .failed(error.localizedDescription)
            throw error
        } catch {
            downloadStatuses[id] = .failed(error.localizedDescription)
            throw AIEngineError.downloadFailed(error)
        }
    }

    /// Cancel an active download.
    ///
    /// Cancels the tracked download Task, which triggers cooperative
    /// cancellation via `Task.isCancelled` in the byte loop.
    public func cancelDownload(id: String) {
        activeDownloadTasks[id]?.cancel()
        activeDownloadTasks[id] = nil
        downloadStatuses[id] = .notDownloaded

        // Clean up partial file
        if let info = Self.availableModelInfos.first(where: { $0.id == id }) {
            let partial = modelPath(for: info).appendingPathExtension("partial")
            try? fileManager.removeItem(at: partial)
        }
    }

    /// Verify the SHA-256 integrity of a downloaded model file.
    ///
    /// Spec ref: AC-A-03 — `verifyIntegrity(path:sha256:)` MUST validate SHA-256 checksum post-download.
    @discardableResult
    public func verifyIntegrity(path: URL, sha256 expectedHash: String) throws -> Bool {
        guard fileManager.fileExists(atPath: path.path) else {
            throw AIEngineError.modelNotFound(path: path.path)
        }

        // Stream hash in chunks to avoid loading entire file into memory (P2-13).
        // For 1 GB+ files, this prevents OOM on memory-constrained devices.
        let handle = try FileHandle(forReadingFrom: path)
        defer { handle.closeFile() }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024 // 1 MB chunks
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: chunkSize)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}

        let digest = hasher.finalize()
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()

        guard actualHash == expectedHash.lowercased() else {
            // Delete corrupt file per AC-A-03
            try? fileManager.removeItem(at: path)
            throw AIEngineError.integrityCheckFailed(expected: expectedHash, actual: actualHash)
        }

        return true
    }

    /// Delete a downloaded model and free storage.
    ///
    /// Spec ref: AC-A-03 — `deleteModel(id:)` MUST remove the file and free storage.
    public func deleteModel(id: String) throws {
        guard let info = Self.availableModelInfos.first(where: { $0.id == id }) else {
            throw AIEngineError.modelNotFound(path: id)
        }

        let path = modelPath(for: info)
        if fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
        }

        // Also clean up partial downloads
        let partial = path.appendingPathExtension("partial")
        try? fileManager.removeItem(at: partial)

        downloadStatuses[id] = .notDownloaded
    }

    /// Total storage used by downloaded models (in bytes).
    ///
    /// Spec ref: AC-A-03 — `storageUsage()` MUST report total model storage accurately.
    public func storageUsage() -> UInt64 {
        guard let enumerator = fileManager.enumerator(at: modelsDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = attrs.fileSize {
                total += UInt64(size)
            }
        }
        return total
    }

    /// Get the file path for a model. Used by `AIEngineResolver` to load into `LlamaEngine`.
    public func modelPath(for info: ModelInfo) -> URL {
        modelsDirectory.appendingPathComponent(info.fileName)
    }

    /// Get the file path for a model by ID.
    public func modelPath(forID id: String) -> URL? {
        guard let info = Self.availableModelInfos.first(where: { $0.id == id }) else {
            return nil
        }
        return modelPath(for: info)
    }

    /// Check if a model is downloaded and available on disk.
    public func isModelDownloaded(id: String) -> Bool {
        guard let info = Self.availableModelInfos.first(where: { $0.id == id }) else {
            return false
        }
        return fileManager.fileExists(atPath: modelPath(for: info).path)
    }

    /// Check if ANY model is downloaded and available on disk.
    ///
    /// Used by UI to determine if AI features should be enabled,
    /// regardless of which specific model the user chose to download.
    public func isAnyModelDownloaded() -> Bool {
        Self.availableModelInfos.contains { info in
            fileManager.fileExists(atPath: modelPath(for: info).path)
        }
    }

    // MARK: - Private

    private func currentStatus(for info: ModelInfo) -> DownloadStatus {
        if let status = downloadStatuses[info.id] {
            return status
        }
        let path = modelPath(for: info)
        return fileManager.fileExists(atPath: path.path) ? .downloaded : .notDownloaded
    }
}
