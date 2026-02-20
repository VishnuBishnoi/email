import Foundation
import Testing
@testable import VaultMailFeature

#if canImport(UserNotifications)
import UserNotifications

@Suite("NotificationContentBuilder")
@MainActor
struct NotificationContentBuilderTests {

    // MARK: - Title Tests

    @Test("Title uses fromName when available")
    func titleUsesFromNameWhenAvailable() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        #expect(content.title == "Sender Name")
    }

    @Test("Title falls back to fromAddress when fromName is nil")
    func titleFallsBackToFromAddressWhenFromNameIsNil() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: nil,
            subject: "Test Subject",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        #expect(content.title == "sender@test.com")
    }

    // MARK: - Subtitle Tests

    @Test("Subtitle is the email subject")
    func subtitleIsEmailSubject() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Important Meeting Tomorrow",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        #expect(content.subtitle == "Important Meeting Tomorrow")
    }

    // MARK: - Body Tests

    @Test("Body is snippet truncated to 100 chars")
    func bodyIsSnippetTruncatedTo100Chars() {
        let longSnippet = String(repeating: "a", count: 150)
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: longSnippet,
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        let expectedBody = String(longSnippet.prefix(100))
        #expect(content.body == expectedBody)
        #expect(content.body.count == 100)
    }

    @Test("Body handles short snippets without truncation")
    func bodyHandlesShortSnippetsWithoutTruncation() {
        let shortSnippet = "This is a short snippet"
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: shortSnippet,
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        #expect(content.body == shortSnippet)
    }

    @Test("Body is empty string when snippet is nil")
    func bodyIsEmptyStringWhenSnippetIsNil() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: nil,
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        #expect(content.body == "")
    }

    // MARK: - Sound Tests

    @Test("Sound is set to default")
    func soundIsSetToDefault() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        #expect(content.sound == .default)
    }

    // MARK: - Category Tests

    @Test("Category identifier is AppConstants.notificationCategoryEmail")
    func categoryIdentifierIsAppConstantsNotificationCategoryEmail() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        #expect(content.categoryIdentifier == AppConstants.notificationCategoryEmail)
    }

    // MARK: - Thread Identifier Tests

    @Test("ThreadIdentifier matches email.threadId")
    func threadIdentifierMatchesEmailThreadId() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread-abc-123",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        #expect(content.threadIdentifier == "thread-abc-123")
    }

    // MARK: - Interruption Level Tests

    @Test("Interruption level is active")
    func interruptionLevelIsActive() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        #expect(content.interruptionLevel == .active)
    }

    // MARK: - UserInfo Tests

    @Test("UserInfo contains emailId key")
    func userInfoContainsEmailIdKey() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        #expect(content.userInfo["emailId"] != nil)
        #expect(content.userInfo["emailId"] as? String == email.id)
    }

    @Test("UserInfo contains threadId key")
    func userInfoContainsThreadIdKey() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread-xyz-789",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        #expect(content.userInfo["threadId"] != nil)
        #expect(content.userInfo["threadId"] as? String == "thread-xyz-789")
    }

    @Test("UserInfo contains accountId key")
    func userInfoContainsAccountIdKey() {
        let email = Email(
            accountId: "account-001",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        #expect(content.userInfo["accountId"] != nil)
        #expect(content.userInfo["accountId"] as? String == "account-001")
    }

    @Test("UserInfo contains fromAddress key")
    func userInfoContainsFromAddressKey() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@example.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        #expect(content.userInfo["fromAddress"] != nil)
        #expect(content.userInfo["fromAddress"] as? String == "sender@example.com")
    }

    @Test("UserInfo contains all 4 keys (emailId, threadId, accountId, fromAddress)")
    func userInfoContainsAll4Keys() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        let expectedKeys = Set(["emailId", "threadId", "accountId", "fromAddress"])
        let actualKeys = Set(content.userInfo.keys.compactMap { $0 as? String })

        #expect(actualKeys == expectedKeys)
    }

    // MARK: - Request Identifier Tests

    @Test("Request identifier format is email-{emailId}")
    func requestIdentifierFormatIsEmailId() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)

        let expectedIdentifier = "email-\(email.id)"
        #expect(request.identifier == expectedIdentifier)
    }

    // MARK: - Trigger Tests

    @Test("Request trigger is nil for immediate delivery")
    func requestTriggerIsNilForImmediateDelivery() {
        let email = Email(
            accountId: "acc1",
            threadId: "thread1",
            messageId: "msg1",
            fromAddress: "sender@test.com",
            fromName: "Sender Name",
            subject: "Test Subject",
            snippet: "Test snippet text",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)

        #expect(request.trigger == nil)
    }

    // MARK: - Integration Tests

    @Test("Complete notification request with all fields")
    func completeNotificationRequestWithAllFields() {
        let email = Email(
            accountId: "acc123",
            threadId: "thread456",
            messageId: "msg789",
            fromAddress: "john@example.com",
            fromName: "John Doe",
            subject: "Meeting Minutes from Q1 Planning Session",
            snippet: "Thank you for attending the Q1 planning session. Here are the key discussion points and action items.",
            dateReceived: Date()
        )

        let request = NotificationContentBuilder.build(from: email)
        let content = request.content

        // Title
        #expect(content.title == "John Doe")

        // Subtitle
        #expect(content.subtitle == "Meeting Minutes from Q1 Planning Session")

        // Body
        #expect(content.body == "Thank you for attending the Q1 planning session. Here are the key discussion points and action items")

        // Sound
        #expect(content.sound == .default)

        // Category
        #expect(content.categoryIdentifier == AppConstants.notificationCategoryEmail)

        // Thread
        #expect(content.threadIdentifier == "thread456")

        // Interruption
        #expect(content.interruptionLevel == .active)

        // UserInfo
        #expect(content.userInfo["emailId"] as? String == email.id)
        #expect(content.userInfo["threadId"] as? String == "thread456")
        #expect(content.userInfo["accountId"] as? String == "acc123")
        #expect(content.userInfo["fromAddress"] as? String == "john@example.com")

        // Request
        #expect(request.identifier == "email-\(email.id)")
        #expect(request.trigger == nil)
    }
}

#endif
