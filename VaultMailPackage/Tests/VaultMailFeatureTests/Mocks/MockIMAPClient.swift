import Foundation
@testable import VaultMailFeature

/// Controllable mock of IMAPClientProtocol for testing.
///
/// Each method has a configurable result and a call counter
/// so tests can verify interactions and simulate errors.
final class MockIMAPClient: IMAPClientProtocol, @unchecked Sendable {

    // MARK: - State

    private(set) var connected = false
    private(set) var selectedFolder: String?

    // MARK: - Call Counts

    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var listFoldersCallCount = 0
    private(set) var selectFolderCallCount = 0
    private(set) var searchUIDsCallCount = 0
    private(set) var searchAllUIDsCallCount = 0
    private(set) var fetchHeadersCallCount = 0
    private(set) var fetchBodiesCallCount = 0
    private(set) var fetchFlagsCallCount = 0
    private(set) var storeFlagsCallCount = 0
    private(set) var copyMessagesCallCount = 0
    private(set) var expungeMessagesCallCount = 0
    private(set) var appendMessageCallCount = 0
    private(set) var fetchBodyPartCallCount = 0
    private(set) var startIDLECallCount = 0
    private(set) var stopIDLECallCount = 0

    // MARK: - Captured Arguments

    private(set) var lastConnectHost: String?
    private(set) var lastConnectPort: Int?
    private(set) var lastConnectEmail: String?
    private(set) var lastConnectAccessToken: String?
    private(set) var lastConnectSecurity: ConnectionSecurity?
    private(set) var lastConnectCredential: IMAPCredential?
    private(set) var lastSelectedPath: String?
    private(set) var lastSearchDate: Date?
    private(set) var lastFetchedUIDs: [UInt32]?
    private(set) var lastStoreFlagUID: UInt32?
    private(set) var lastStoreFlagAdd: [String]?
    private(set) var lastStoreFlagRemove: [String]?
    private(set) var lastCopyUIDs: [UInt32]?
    private(set) var lastCopyDestination: String?
    private(set) var lastExpungeUIDs: [UInt32]?
    private(set) var lastAppendPath: String?
    private(set) var lastAppendData: Data?
    private(set) var lastAppendFlags: [String]?
    private(set) var lastFetchBodyPartUID: UInt32?
    private(set) var lastFetchBodyPartSection: String?

    // MARK: - Configurable Results

    var connectError: IMAPError?
    var disconnectError: IMAPError?
    var listFoldersResult: Result<[IMAPFolderInfo], IMAPError> = .success([])
    var selectFolderResult: Result<(uidValidity: UInt32, messageCount: UInt32), IMAPError> = .success((1, 0))
    var searchUIDsResult: Result<[UInt32], IMAPError> = .success([])
    /// When nil, falls back to `searchUIDsResult` for backward compatibility
    /// with existing tests that only configure `searchUIDsResult`.
    var searchAllUIDsResult: Result<[UInt32], IMAPError>?
    var fetchHeadersResult: Result<[IMAPEmailHeader], IMAPError> = .success([])
    var fetchBodiesResult: Result<[IMAPEmailBody], IMAPError> = .success([])
    var fetchFlagsResult: Result<[UInt32: [String]], IMAPError> = .success([:])
    var storeFlagsError: IMAPError?
    var copyMessagesError: IMAPError?
    var expungeMessagesError: IMAPError?
    var appendMessageError: IMAPError?
    var fetchBodyPartResult: Result<Data, IMAPError> = .success(Data())
    var startIDLEError: IMAPError?
    var stopIDLEError: IMAPError?

    // MARK: - IDLE Configuration

    var idleRefreshInterval: TimeInterval = 25 * 60

    // MARK: - IDLE Callback

    private(set) var idleHandler: (@Sendable () -> Void)?

    /// Simulate new mail arriving while IDLE is active.
    func simulateNewMail() {
        idleHandler?()
    }

    // MARK: - IMAPClientProtocol

    var isConnected: Bool {
        get async { connected }
    }

    func connect(host: String, port: Int, security: ConnectionSecurity, credential: IMAPCredential) async throws {
        connectCallCount += 1
        lastConnectHost = host
        lastConnectPort = port
        lastConnectSecurity = security
        lastConnectCredential = credential

        // Also populate legacy fields for backward-compat assertions
        switch credential {
        case .xoauth2(let email, let accessToken):
            lastConnectEmail = email
            lastConnectAccessToken = accessToken
        case .plain(let username, _):
            lastConnectEmail = username
        }

        if let error = connectError {
            throw error
        }
        connected = true
    }

    func connect(host: String, port: Int, email: String, accessToken: String) async throws {
        try await connect(
            host: host,
            port: port,
            security: .tls,
            credential: .xoauth2(email: email, accessToken: accessToken)
        )
    }

    func disconnect() async throws {
        disconnectCallCount += 1
        if let error = disconnectError {
            throw error
        }
        connected = false
        selectedFolder = nil
    }

    func listFolders() async throws -> [IMAPFolderInfo] {
        listFoldersCallCount += 1
        return try listFoldersResult.get()
    }

    func selectFolder(_ imapPath: String) async throws -> (uidValidity: UInt32, messageCount: UInt32) {
        selectFolderCallCount += 1
        lastSelectedPath = imapPath
        selectedFolder = imapPath
        return try selectFolderResult.get()
    }

    func searchUIDs(since date: Date) async throws -> [UInt32] {
        searchUIDsCallCount += 1
        lastSearchDate = date
        return try searchUIDsResult.get()
    }

    func searchAllUIDs() async throws -> [UInt32] {
        searchAllUIDsCallCount += 1
        // Fall back to searchUIDsResult if searchAllUIDsResult was not explicitly set.
        // This preserves backward compatibility with tests that only configure searchUIDsResult.
        return try (searchAllUIDsResult ?? searchUIDsResult).get()
    }

    func fetchHeaders(uids: [UInt32]) async throws -> [IMAPEmailHeader] {
        fetchHeadersCallCount += 1
        lastFetchedUIDs = uids
        return try fetchHeadersResult.get()
    }

    func fetchBodies(uids: [UInt32]) async throws -> [IMAPEmailBody] {
        fetchBodiesCallCount += 1
        lastFetchedUIDs = uids
        return try fetchBodiesResult.get()
    }

    func fetchFlags(uids: [UInt32]) async throws -> [UInt32: [String]] {
        fetchFlagsCallCount += 1
        lastFetchedUIDs = uids
        return try fetchFlagsResult.get()
    }

    func storeFlags(uid: UInt32, add: [String], remove: [String]) async throws {
        storeFlagsCallCount += 1
        lastStoreFlagUID = uid
        lastStoreFlagAdd = add
        lastStoreFlagRemove = remove
        if let error = storeFlagsError {
            throw error
        }
    }

    func copyMessages(uids: [UInt32], to destinationPath: String) async throws {
        copyMessagesCallCount += 1
        lastCopyUIDs = uids
        lastCopyDestination = destinationPath
        if let error = copyMessagesError {
            throw error
        }
    }

    func expungeMessages(uids: [UInt32]) async throws {
        expungeMessagesCallCount += 1
        lastExpungeUIDs = uids
        if let error = expungeMessagesError {
            throw error
        }
    }

    func appendMessage(to imapPath: String, messageData: Data, flags: [String]) async throws {
        appendMessageCallCount += 1
        lastAppendPath = imapPath
        lastAppendData = messageData
        lastAppendFlags = flags
        if let error = appendMessageError {
            throw error
        }
    }

    func fetchBodyPart(uid: UInt32, section: String) async throws -> Data {
        fetchBodyPartCallCount += 1
        lastFetchBodyPartUID = uid
        lastFetchBodyPartSection = section
        return try fetchBodyPartResult.get()
    }

    func startIDLE(onNewMail: @Sendable @escaping () -> Void) async throws {
        startIDLECallCount += 1
        if let error = startIDLEError {
            throw error
        }
        idleHandler = onNewMail
    }

    func stopIDLE() async throws {
        stopIDLECallCount += 1
        if let error = stopIDLEError {
            throw error
        }
        idleHandler = nil
    }
}
