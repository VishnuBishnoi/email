import Foundation

/// Errors from Keychain operations.
///
/// Spec ref: Account Management spec FR-ACCT-04
public enum KeychainError: Error, LocalizedError, Sendable {
    case itemNotFound
    case unableToStore(OSStatus)
    case unableToRetrieve(OSStatus)
    case unableToDelete(OSStatus)
    case encodingFailed
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            "Keychain item not found."
        case .unableToStore(let status):
            "Unable to store item in Keychain (status: \(status))."
        case .unableToRetrieve(let status):
            "Unable to retrieve item from Keychain (status: \(status))."
        case .unableToDelete(let status):
            "Unable to delete item from Keychain (status: \(status))."
        case .encodingFailed:
            "Failed to encode token data."
        case .decodingFailed:
            "Failed to decode token data."
        }
    }
}
