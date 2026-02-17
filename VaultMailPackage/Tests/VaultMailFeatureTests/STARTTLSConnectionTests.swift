import Foundation
import Testing
@testable import VaultMailFeature

// MARK: - ConnectionSecurity Tests

@Suite("ConnectionSecurity — IOS-MP-03")
struct ConnectionSecurityTests {

    // MARK: - Raw Values

    @Test("tls raw value is 'tls'")
    func tlsRawValue() {
        #expect(ConnectionSecurity.tls.rawValue == "tls")
    }

    @Test("starttls raw value is 'starttls'")
    func starttlsRawValue() {
        #expect(ConnectionSecurity.starttls.rawValue == "starttls")
    }

    #if DEBUG
    @Test("none raw value is 'none' (debug only)")
    func noneRawValue() {
        #expect(ConnectionSecurity.none.rawValue == "none")
    }
    #endif

    // MARK: - CaseIterable

    @Test("allCases contains tls and starttls")
    func allCasesContainsExpectedCases() {
        let cases = ConnectionSecurity.allCases
        #expect(cases.contains(.tls))
        #expect(cases.contains(.starttls))
    }

    #if DEBUG
    @Test("allCases has 3 cases in debug builds")
    func allCasesCountDebug() {
        #expect(ConnectionSecurity.allCases.count == 3)
    }
    #endif

    // MARK: - Codable

    @Test("Codable roundtrip for tls")
    func codableRoundtripTLS() throws {
        let original = ConnectionSecurity.tls
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectionSecurity.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable roundtrip for starttls")
    func codableRoundtripSTARTTLS() throws {
        let original = ConnectionSecurity.starttls
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectionSecurity.self, from: data)
        #expect(decoded == original)
    }

    @Test("tls encodes as the string 'tls'")
    func tlsEncodesToExpectedString() throws {
        let data = try JSONEncoder().encode(ConnectionSecurity.tls)
        let jsonString = String(data: data, encoding: .utf8)
        #expect(jsonString == "\"tls\"")
    }

    @Test("starttls encodes as the string 'starttls'")
    func starttlsEncodesToExpectedString() throws {
        let data = try JSONEncoder().encode(ConnectionSecurity.starttls)
        let jsonString = String(data: data, encoding: .utf8)
        #expect(jsonString == "\"starttls\"")
    }

    @Test("Decoding invalid string throws")
    func decodingInvalidThrows() throws {
        let jsonData = Data("\"invalid\"".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ConnectionSecurity.self, from: jsonData)
        }
    }

    // MARK: - Sendable

    @Test("ConnectionSecurity can cross concurrency boundaries")
    func sendableConformance() async {
        let security: ConnectionSecurity = .starttls
        let result = await Task { security }.value
        #expect(result == .starttls)
    }

    // MARK: - Equatable

    @Test("Equatable: same cases are equal")
    func equatableSameCases() {
        #expect(ConnectionSecurity.tls == ConnectionSecurity.tls)
        #expect(ConnectionSecurity.starttls == ConnectionSecurity.starttls)
    }

    @Test("Equatable: different cases are not equal")
    func equatableDifferentCases() {
        #expect(ConnectionSecurity.tls != ConnectionSecurity.starttls)
    }

    // MARK: - Init from raw value

    @Test("Init from raw value 'tls'")
    func initFromRawTLS() {
        let security = ConnectionSecurity(rawValue: "tls")
        #expect(security == .tls)
    }

    @Test("Init from raw value 'starttls'")
    func initFromRawSTARTTLS() {
        let security = ConnectionSecurity(rawValue: "starttls")
        #expect(security == .starttls)
    }

    @Test("Init from invalid raw value returns nil")
    func initFromInvalidRaw() {
        let security = ConnectionSecurity(rawValue: "ssl")
        #expect(security == nil)
    }
}

// MARK: - ConnectionError Tests

@Suite("ConnectionError — IOS-MP-03")
struct ConnectionErrorTests {

    // MARK: - Error Descriptions

    @Test("connectionFailed includes the message")
    func connectionFailedDescription() {
        let error = ConnectionError.connectionFailed("host unreachable")
        #expect(error.errorDescription?.contains("host unreachable") == true)
        #expect(error.errorDescription?.contains("Connection Failed") == true)
    }

    @Test("timeout has a fixed description")
    func timeoutDescription() {
        let error = ConnectionError.timeout
        #expect(error.errorDescription?.contains("Timed Out") == true)
    }

    @Test("tlsUpgradeFailed includes the message")
    func tlsUpgradeFailedDescription() {
        let error = ConnectionError.tlsUpgradeFailed("handshake error")
        #expect(error.errorDescription?.contains("handshake error") == true)
        #expect(error.errorDescription?.contains("TLS Upgrade Failed") == true)
    }

    @Test("certificateValidationFailed includes the message")
    func certificateValidationFailedDescription() {
        let error = ConnectionError.certificateValidationFailed("self-signed")
        #expect(error.errorDescription?.contains("self-signed") == true)
        #expect(error.errorDescription?.contains("Certificate Validation Failed") == true)
    }

    @Test("invalidResponse includes the message")
    func invalidResponseDescription() {
        let error = ConnectionError.invalidResponse("garbled data")
        #expect(error.errorDescription?.contains("garbled data") == true)
        #expect(error.errorDescription?.contains("Invalid Response") == true)
    }

    // MARK: - Equatable

    @Test("Same connectionFailed messages are equal")
    func connectionFailedEquatable() {
        let a = ConnectionError.connectionFailed("error A")
        let b = ConnectionError.connectionFailed("error A")
        #expect(a == b)
    }

    @Test("Different connectionFailed messages are not equal")
    func connectionFailedNotEquatable() {
        let a = ConnectionError.connectionFailed("error A")
        let b = ConnectionError.connectionFailed("error B")
        #expect(a != b)
    }

    @Test("timeout equals timeout")
    func timeoutEquatable() {
        #expect(ConnectionError.timeout == ConnectionError.timeout)
    }

    @Test("Different error cases are not equal")
    func differentCasesNotEqual() {
        #expect(ConnectionError.timeout != ConnectionError.connectionFailed("timeout"))
        #expect(ConnectionError.tlsUpgradeFailed("x") != ConnectionError.certificateValidationFailed("x"))
    }

    // MARK: - Sendable

    @Test("ConnectionError can cross concurrency boundaries")
    func sendableConformance() async {
        let error = ConnectionError.timeout
        let result = await Task { error }.value
        #expect(result == .timeout)
    }
}

// MARK: - STARTTLSConnection Tests

@Suite("STARTTLSConnection — IOS-MP-03, FR-MPROV-05")
struct STARTTLSConnectionTests {

    // MARK: - Factory

    private func makeSUT(timeout: TimeInterval = 5) -> STARTTLSConnection {
        STARTTLSConnection(timeout: timeout)
    }

    // MARK: - Initial State

    @Test("isConnected is false before connect")
    func initialNotConnected() async {
        let sut = makeSUT()
        let connected = await sut.isConnected
        #expect(connected == false)
    }

    @Test("isTLSUpgraded is false before any TLS upgrade")
    func initialNotTLSUpgraded() async {
        let sut = makeSUT()
        let upgraded = await sut.isTLSUpgraded
        #expect(upgraded == false)
    }

    // MARK: - Not Connected Guards

    @Test("upgradeTLS throws connectionFailed when not connected")
    func upgradeTLSWhenNotConnected() async {
        let sut = makeSUT()
        await #expect(throws: ConnectionError.self) {
            try await sut.upgradeTLS(host: "example.com")
        }
    }

    @Test("upgradeTLS throws with 'Not connected' message when not connected")
    func upgradeTLSNotConnectedMessage() async {
        let sut = makeSUT()
        do {
            try await sut.upgradeTLS(host: "example.com")
            Issue.record("Expected error to be thrown")
        } catch {
            let connError = error as? ConnectionError
            #expect(connError == .connectionFailed("Not connected"))
        }
    }

    @Test("send throws connectionFailed when not connected")
    func sendWhenNotConnected() async {
        let sut = makeSUT()
        await #expect(throws: ConnectionError.self) {
            try await sut.send(Data("test".utf8))
        }
    }

    @Test("sendLine throws connectionFailed when not connected")
    func sendLineWhenNotConnected() async {
        let sut = makeSUT()
        await #expect(throws: ConnectionError.self) {
            try await sut.sendLine("CAPABILITY")
        }
    }

    @Test("receiveData throws connectionFailed when not connected")
    func receiveDataWhenNotConnected() async {
        let sut = makeSUT()
        await #expect(throws: ConnectionError.self) {
            try await sut.receiveData()
        }
    }

    @Test("readLine throws connectionFailed when not connected")
    func readLineWhenNotConnected() async {
        let sut = makeSUT()
        await #expect(throws: ConnectionError.self) {
            try await sut.readLine()
        }
    }

    @Test("readSMTPResponse throws when not connected")
    func readSMTPResponseWhenNotConnected() async {
        let sut = makeSUT()
        await #expect(throws: ConnectionError.self) {
            try await sut.readSMTPResponse()
        }
    }

    // MARK: - Disconnect

    @Test("disconnect sets isConnected to false")
    func disconnectResetsIsConnected() async {
        let sut = makeSUT()
        await sut.disconnect()
        let connected = await sut.isConnected
        #expect(connected == false)
    }

    @Test("disconnect sets isTLSUpgraded to false")
    func disconnectResetsIsTLSUpgraded() async {
        let sut = makeSUT()
        await sut.disconnect()
        let upgraded = await sut.isTLSUpgraded
        #expect(upgraded == false)
    }

    @Test("disconnect is safe to call multiple times")
    func disconnectIdempotent() async {
        let sut = makeSUT()
        await sut.disconnect()
        await sut.disconnect()
        await sut.disconnect()
        let connected = await sut.isConnected
        #expect(connected == false)
    }
}

// MARK: - IMAP Error Mapping Tests (STARTTLS cases)

@Suite("IMAPError STARTTLS cases — IOS-MP-03")
struct IMAPErrorSTARTTLSTests {

    @Test("starttlsNotSupported has correct description")
    func starttlsNotSupportedDescription() {
        let error = IMAPError.starttlsNotSupported
        #expect(error.errorDescription?.contains("STARTTLS Not Supported") == true)
    }

    @Test("tlsUpgradeFailed includes the message")
    func tlsUpgradeFailedDescription() {
        let error = IMAPError.tlsUpgradeFailed("handshake timeout")
        #expect(error.errorDescription?.contains("handshake timeout") == true)
        #expect(error.errorDescription?.contains("TLS Upgrade Failed") == true)
    }

    @Test("certificateValidationFailed includes the message")
    func certificateValidationFailedDescription() {
        let error = IMAPError.certificateValidationFailed("untrusted root")
        #expect(error.errorDescription?.contains("untrusted root") == true)
        #expect(error.errorDescription?.contains("Certificate Validation Failed") == true)
    }

    @Test("STARTTLS error cases are Equatable")
    func starttlsErrorsEquatable() {
        #expect(IMAPError.starttlsNotSupported == IMAPError.starttlsNotSupported)
        #expect(IMAPError.tlsUpgradeFailed("x") == IMAPError.tlsUpgradeFailed("x"))
        #expect(IMAPError.tlsUpgradeFailed("x") != IMAPError.tlsUpgradeFailed("y"))
        #expect(IMAPError.certificateValidationFailed("a") == IMAPError.certificateValidationFailed("a"))
    }

    @Test("STARTTLS errors are different from other IMAP errors")
    func starttlsErrorsDifferentFromOthers() {
        #expect(IMAPError.starttlsNotSupported != IMAPError.timeout)
        #expect(IMAPError.tlsUpgradeFailed("x") != IMAPError.connectionFailed("x"))
    }
}

// MARK: - SMTP Error Mapping Tests (STARTTLS cases)

@Suite("SMTPError STARTTLS cases — IOS-MP-03")
struct SMTPErrorSTARTTLSTests {

    @Test("starttlsNotSupported has correct description")
    func starttlsNotSupportedDescription() {
        let error = SMTPError.starttlsNotSupported
        #expect(error.errorDescription?.contains("STARTTLS Not Supported") == true)
    }

    @Test("tlsUpgradeFailed includes the message")
    func tlsUpgradeFailedDescription() {
        let error = SMTPError.tlsUpgradeFailed("certificate rejected")
        #expect(error.errorDescription?.contains("certificate rejected") == true)
        #expect(error.errorDescription?.contains("TLS Upgrade Failed") == true)
    }

    @Test("certificateValidationFailed includes the message")
    func certificateValidationFailedDescription() {
        let error = SMTPError.certificateValidationFailed("self-signed cert")
        #expect(error.errorDescription?.contains("self-signed cert") == true)
        #expect(error.errorDescription?.contains("Certificate Validation Failed") == true)
    }

    @Test("SMTP STARTTLS errors are Equatable")
    func smtpStarttlsErrorsEquatable() {
        #expect(SMTPError.starttlsNotSupported == SMTPError.starttlsNotSupported)
        #expect(SMTPError.tlsUpgradeFailed("x") == SMTPError.tlsUpgradeFailed("x"))
        #expect(SMTPError.tlsUpgradeFailed("x") != SMTPError.tlsUpgradeFailed("y"))
        #expect(SMTPError.certificateValidationFailed("a") == SMTPError.certificateValidationFailed("a"))
    }

    @Test("SMTP STARTTLS errors are different from other SMTP errors")
    func smtpStarttlsErrorsDifferentFromOthers() {
        #expect(SMTPError.starttlsNotSupported != SMTPError.timeout)
        #expect(SMTPError.tlsUpgradeFailed("x") != SMTPError.connectionFailed("x"))
    }
}

// MARK: - IMAPSession State Tests

@Suite("IMAPSession STARTTLS state — IOS-MP-03")
struct IMAPSessionSTARTTLSTests {

    @Test("IMAPSession is not connected initially")
    func initialNotConnected() async {
        let sut = IMAPSession(timeout: 1)
        let connected = await sut.isSessionConnected
        #expect(connected == false)
    }

    @Test("disconnect when not connected does not crash")
    func disconnectWhenNotConnected() async {
        let sut = IMAPSession(timeout: 1)
        await sut.disconnect()
        let connected = await sut.isSessionConnected
        #expect(connected == false)
    }

    @Test("disconnect is idempotent")
    func disconnectIdempotent() async {
        let sut = IMAPSession(timeout: 1)
        await sut.disconnect()
        await sut.disconnect()
        let connected = await sut.isSessionConnected
        #expect(connected == false)
    }
}

// MARK: - SMTPSession State Tests

@Suite("SMTPSession STARTTLS state — IOS-MP-03")
struct SMTPSessionSTARTTLSTests {

    @Test("SMTPSession is not connected initially")
    func initialNotConnected() async {
        let sut = SMTPSession(timeout: 1)
        let connected = await sut.isSessionConnected
        #expect(connected == false)
    }

    @Test("disconnect when not connected does not crash")
    func disconnectWhenNotConnected() async {
        let sut = SMTPSession(timeout: 1)
        await sut.disconnect()
        let connected = await sut.isSessionConnected
        #expect(connected == false)
    }

    @Test("disconnect is idempotent")
    func disconnectIdempotent() async {
        let sut = SMTPSession(timeout: 1)
        await sut.disconnect()
        await sut.disconnect()
        let connected = await sut.isSessionConnected
        #expect(connected == false)
    }
}
