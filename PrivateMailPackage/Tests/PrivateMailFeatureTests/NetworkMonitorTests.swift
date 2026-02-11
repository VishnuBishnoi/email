#if os(iOS)
import Foundation
import Testing
@testable import PrivateMailFeature

@Suite("NetworkMonitor")
@MainActor
struct NetworkMonitorTests {

    @Test("init succeeds without crash")
    func initDoesNotCrash() {
        let monitor = NetworkMonitor()
        _ = monitor
    }

    @Test("default isConnected is true")
    func defaultIsConnectedTrue() {
        let monitor = NetworkMonitor()
        #expect(monitor.isConnected == true)
    }

    @Test("default isCellular is false")
    func defaultIsCellularFalse() {
        let monitor = NetworkMonitor()
        #expect(monitor.isCellular == false)
    }
}
#endif
