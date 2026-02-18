import Foundation
@testable import VaultMailFeature

/// In-memory mock of SMTPClientProtocol for testing.
actor MockSMTPClient: SMTPClientProtocol {
    var connectCallCount = 0
    var disconnectCallCount = 0
    var sendMessageCallCount = 0
    var _isConnected = false
    var shouldThrowOnConnect = false
    var shouldThrowOnSend = false
    var connectError: SMTPError = .connectionFailed("mock error")
    var sendError: SMTPError = .commandFailed("mock error")

    var lastConnectHost: String?
    var lastConnectPort: Int?
    var lastConnectSecurity: ConnectionSecurity?
    var lastConnectCredential: SMTPCredential?

    var lastFrom: String?
    var lastRecipients: [String]?
    var lastMessageData: Data?

    var isConnected: Bool {
        _isConnected
    }

    func setThrowOnConnect(_ value: Bool) {
        shouldThrowOnConnect = value
    }

    func setThrowOnSend(_ value: Bool) {
        shouldThrowOnSend = value
    }

    func connect(host: String, port: Int, security: ConnectionSecurity, credential: SMTPCredential) async throws {
        connectCallCount += 1
        lastConnectHost = host
        lastConnectPort = port
        lastConnectSecurity = security
        lastConnectCredential = credential
        if shouldThrowOnConnect {
            throw connectError
        }
        _isConnected = true
    }

    func connect(host: String, port: Int, email: String, accessToken: String) async throws {
        try await connect(
            host: host,
            port: port,
            security: .tls,
            credential: .xoauth2(email: email, accessToken: accessToken)
        )
    }

    func disconnect() async {
        disconnectCallCount += 1
        _isConnected = false
    }

    func sendMessage(from: String, recipients: [String], messageData: Data) async throws {
        sendMessageCallCount += 1
        lastFrom = from
        lastRecipients = recipients
        lastMessageData = messageData
        if shouldThrowOnSend {
            throw sendError
        }
    }
}
