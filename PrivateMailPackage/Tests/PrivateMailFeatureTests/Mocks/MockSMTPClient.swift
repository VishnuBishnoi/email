import Foundation
@testable import PrivateMailFeature

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

    var lastFrom: String?
    var lastRecipients: [String]?
    var lastMessageData: Data?

    var isConnected: Bool {
        _isConnected
    }

    func connect(host: String, port: Int, email: String, accessToken: String) async throws {
        connectCallCount += 1
        if shouldThrowOnConnect {
            throw connectError
        }
        _isConnected = true
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
