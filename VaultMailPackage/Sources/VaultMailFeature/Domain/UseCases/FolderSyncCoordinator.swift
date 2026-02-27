import Foundation

/// Coordinates per-folder sync writes so only one mutating sync runs at a time.
///
/// Spec ref: FR-SYNC-03 (single-writer lock for IDLE/incremental/catch-up overlap)
public actor FolderSyncCoordinator {
    private var activeKeys = Set<String>()
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    public init() {}

    public func acquire(accountId: String, folderId: String) async {
        let key = makeKey(accountId: accountId, folderId: folderId)
        if !activeKeys.contains(key) {
            activeKeys.insert(key)
            return
        }

        await withCheckedContinuation { continuation in
            waiters[key, default: []].append(continuation)
        }
    }

    public func release(accountId: String, folderId: String) {
        let key = makeKey(accountId: accountId, folderId: folderId)
        if var queue = waiters[key], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[key] = queue.isEmpty ? nil : queue
            next.resume()
            return
        }
        activeKeys.remove(key)
    }

    private func makeKey(accountId: String, folderId: String) -> String {
        "\(accountId)::\(folderId)"
    }
}
