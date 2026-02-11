#if os(iOS)
import Foundation
import Testing
@testable import VaultMailFeature

@Suite("NetworkMonitor")
@MainActor
struct NetworkMonitorTests {

    @Test("init succeeds without crash")
    func initDoesNotCrash() {
        let monitor = NetworkMonitor()
        defer { monitor.cancel() }
        _ = monitor
    }

    @Test("default isConnected is true")
    func defaultIsConnectedTrue() {
        let monitor = NetworkMonitor()
        defer { monitor.cancel() }
        #expect(monitor.isConnected == true)
    }

    @Test("default isCellular is false")
    func defaultIsCellularFalse() {
        let monitor = NetworkMonitor()
        defer { monitor.cancel() }
        #expect(monitor.isCellular == false)
    }
}
#endif
