import Foundation
import LocalAuthentication

/// Protocol for biometric/passcode evaluation, wrapping LAContext for testability.
public protocol BiometricEvaluating: Sendable {
    /// Whether device owner authentication (biometric or passcode) is available.
    func canEvaluatePolicy() -> Bool
    /// Evaluate device owner authentication. Presents system biometric/passcode prompt.
    func evaluatePolicy(localizedReason: String) async throws -> Bool
}

/// Default implementation using LAContext.
public struct SystemBiometricEvaluator: BiometricEvaluating {
    public init() {}

    public func canEvaluatePolicy() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    public func evaluatePolicy(localizedReason: String) async throws -> Bool {
        let context = LAContext()
        return try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: localizedReason
        )
    }
}

/// Manages app lock state using biometric/passcode authentication.
///
/// App lock applies at the app boundary only: cold launch and return from
/// background. There is no within-app re-authentication in V1.
///
/// Uses `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` which handles
/// Face ID, Touch ID, and device passcode fallback automatically.
///
/// Spec ref: FR-SET-01 Security section, Foundation Section 9.2
@Observable
@MainActor
public final class AppLockManager {

    private let evaluator: BiometricEvaluating

    /// Whether the app is currently locked (requires authentication to proceed).
    public var isLocked: Bool = false

    /// Whether biometric/passcode authentication is available on this device.
    public var isAvailable: Bool {
        evaluator.canEvaluatePolicy()
    }

    /// Creates an AppLockManager.
    /// - Parameter evaluator: Biometric evaluator. Defaults to system LAContext.
    public init(evaluator: BiometricEvaluating = SystemBiometricEvaluator()) {
        self.evaluator = evaluator
    }

    /// Attempt to authenticate the user via biometric or device passcode.
    /// Updates `isLocked` on success.
    /// - Returns: `true` if authentication succeeded.
    @discardableResult
    public func authenticate() async -> Bool {
        do {
            let success = try await evaluator.evaluatePolicy(
                localizedReason: "Unlock PrivateMail"
            )
            if success {
                isLocked = false
            }
            return success
        } catch {
            // Authentication failed or was cancelled
            return false
        }
    }

    /// Lock the app. Called when app enters background (if app lock is enabled).
    public func lock() {
        isLocked = true
    }
}
