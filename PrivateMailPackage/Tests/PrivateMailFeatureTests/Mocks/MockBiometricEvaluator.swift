import Foundation
@testable import PrivateMailFeature

/// Controllable mock of BiometricEvaluating for testing AppLockManager.
final class MockBiometricEvaluator: BiometricEvaluating, @unchecked Sendable {
    var canEvaluateResult = true
    var evaluateResult = true
    var shouldThrowOnEvaluate = false
    var evaluateCallCount = 0

    func canEvaluatePolicy() -> Bool {
        canEvaluateResult
    }

    func evaluatePolicy(localizedReason: String) async throws -> Bool {
        evaluateCallCount += 1
        if shouldThrowOnEvaluate {
            throw NSError(domain: LAErrorDomain, code: -2, userInfo: nil)
        }
        return evaluateResult
    }
}

private let LAErrorDomain = "com.apple.LocalAuthentication"
