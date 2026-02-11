import Foundation
import Testing
@testable import VaultMailFeature

@Suite("AppLockManager")
struct AppLockManagerTests {

    @Test("isAvailable reflects evaluator capability")
    @MainActor
    func isAvailable() {
        let evaluator = MockBiometricEvaluator()

        evaluator.canEvaluateResult = true
        let manager1 = AppLockManager(evaluator: evaluator)
        #expect(manager1.isAvailable == true)

        evaluator.canEvaluateResult = false
        let manager2 = AppLockManager(evaluator: evaluator)
        #expect(manager2.isAvailable == false)
    }

    @Test("authenticate returns true on success and unlocks")
    @MainActor
    func authenticateSuccess() async {
        let evaluator = MockBiometricEvaluator()
        evaluator.evaluateResult = true
        let manager = AppLockManager(evaluator: evaluator)
        manager.isLocked = true

        let result = await manager.authenticate()

        #expect(result == true)
        #expect(manager.isLocked == false)
        #expect(evaluator.evaluateCallCount == 1)
    }

    @Test("authenticate returns false on failure and stays locked")
    @MainActor
    func authenticateFailure() async {
        let evaluator = MockBiometricEvaluator()
        evaluator.evaluateResult = false
        let manager = AppLockManager(evaluator: evaluator)
        manager.isLocked = true

        let result = await manager.authenticate()

        #expect(result == false)
        #expect(manager.isLocked == true)
    }

    @Test("authenticate returns false on error and stays locked")
    @MainActor
    func authenticateError() async {
        let evaluator = MockBiometricEvaluator()
        evaluator.shouldThrowOnEvaluate = true
        let manager = AppLockManager(evaluator: evaluator)
        manager.isLocked = true

        let result = await manager.authenticate()

        #expect(result == false)
        #expect(manager.isLocked == true)
    }

    @Test("lock sets isLocked to true")
    @MainActor
    func lockSetsState() {
        let evaluator = MockBiometricEvaluator()
        let manager = AppLockManager(evaluator: evaluator)
        #expect(manager.isLocked == false)

        manager.lock()

        #expect(manager.isLocked == true)
    }

    @Test("initial state is unlocked")
    @MainActor
    func initialStateUnlocked() {
        let manager = AppLockManager(evaluator: MockBiometricEvaluator())
        #expect(manager.isLocked == false)
    }
}
