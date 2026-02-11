#if os(iOS)
import Foundation
import Network
import Observation

/// Observable wrapper around `NWPathMonitor` for reliable network status detection.
///
/// `NWPathMonitor.currentPath` is unreliable until the monitor has been started
/// on a dispatch queue and received its first path update. This service starts
/// monitoring immediately on init and exposes the current path state as
/// observable properties.
///
/// Usage: Create as `@State` in a parent view and inject via `.environment()`,
/// or use `@Environment(NetworkMonitor.self)` in child views.
///
/// PR #8 Comment 7: Replaces ad-hoc `NWPathMonitor` usage in AttachmentRowView.
@Observable
@MainActor
public final class NetworkMonitor {

    /// `true` when the current network path uses a cellular interface.
    public private(set) var isCellular = false

    /// `true` when the network is reachable.
    public private(set) var isConnected = true

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.vaultmail.networkmonitor")

    public init() {
        self.monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isCellular = path.usesInterfaceType(.cellular)
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    /// Stops monitoring. Safe to call multiple times.
    ///
    /// Called automatically on deinit, but call it early to release
    /// the underlying dispatch queue (important in unit tests where
    /// `NWPathMonitor`'s queue can prevent process exit on Simulator).
    public func cancel() {
        monitor.cancel()
    }

    deinit {
        monitor.cancel()
    }
}
#endif
