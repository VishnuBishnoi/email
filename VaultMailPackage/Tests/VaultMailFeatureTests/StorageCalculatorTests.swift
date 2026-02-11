import Foundation
import SwiftData
import Testing
@testable import VaultMailFeature

@Suite("StorageCalculator")
struct StorageCalculatorTests {

    @MainActor
    private static func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.createForTesting()
    }

    // MARK: - Empty State

    @Test("Empty database returns zero storage")
    @MainActor
    func emptyDatabase() async throws {
        let container = try Self.makeContainer()
        let calculator = StorageCalculator(modelContainer: container)

        let info = try await calculator.calculateStorage()

        #expect(info.accounts.isEmpty)
        #expect(info.totalBytes == 0)
        #expect(info.aiModelSizeBytes == 0)
        #expect(info.exceedsWarningThreshold == false)
    }

    // MARK: - Per-Account Breakdown

    @Test("Calculates email sizes for a single account")
    @MainActor
    func singleAccountEmailSizes() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        // Create account
        let account = Account(id: "acc-1", email: "user@gmail.com", displayName: "User")
        context.insert(account)

        // Create thread (required parent for emails)
        let thread = Thread(
            id: "thread-1",
            accountId: "acc-1",
            subject: "Test",
            messageCount: 2,
            unreadCount: 0,
            isStarred: false
        )
        context.insert(thread)

        // Create emails with known sizes
        let email1 = Email(
            id: "email-1", accountId: "acc-1", threadId: "thread-1",
            messageId: "<1@test>", fromAddress: "a@b.com",
            subject: "Test 1", sizeBytes: 1000, sendState: SendState.none.rawValue
        )
        email1.thread = thread
        context.insert(email1)

        let email2 = Email(
            id: "email-2", accountId: "acc-1", threadId: "thread-1",
            messageId: "<2@test>", fromAddress: "a@b.com",
            subject: "Test 2", sizeBytes: 2000, sendState: SendState.none.rawValue
        )
        email2.thread = thread
        context.insert(email2)

        try context.save()

        let calculator = StorageCalculator(modelContainer: container)
        let info = try await calculator.calculateStorage()

        #expect(info.accounts.count == 1)
        let accountInfo = try #require(info.accounts.first)
        #expect(accountInfo.accountId == "acc-1")
        #expect(accountInfo.email == "user@gmail.com")
        #expect(accountInfo.emailCount == 2)
        #expect(accountInfo.estimatedEmailSizeBytes == 3000) // 1000 + 2000
        #expect(accountInfo.searchIndexSizeBytes == 300) // 10% of 3000
    }

    @Test("Calculates downloaded attachment sizes")
    @MainActor
    func attachmentSizes() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        let account = Account(id: "acc-1", email: "user@gmail.com", displayName: "User")
        context.insert(account)

        let thread = Thread(
            id: "thread-1", accountId: "acc-1", subject: "Test",
            messageCount: 1, unreadCount: 0, isStarred: false
        )
        context.insert(thread)

        let email = Email(
            id: "email-1", accountId: "acc-1", threadId: "thread-1",
            messageId: "<1@test>", fromAddress: "a@b.com",
            subject: "Test", sizeBytes: 500, sendState: SendState.none.rawValue
        )
        email.thread = thread
        context.insert(email)

        // Downloaded attachment (counted)
        let att1 = Attachment(
            id: "att-1", filename: "doc.pdf", mimeType: "application/pdf",
            sizeBytes: 5000, isDownloaded: true
        )
        att1.email = email
        context.insert(att1)

        // Not downloaded attachment (not counted)
        let att2 = Attachment(
            id: "att-2", filename: "img.png", mimeType: "image/png",
            sizeBytes: 3000, isDownloaded: false
        )
        att2.email = email
        context.insert(att2)

        try context.save()

        let calculator = StorageCalculator(modelContainer: container)
        let info = try await calculator.calculateStorage()

        let accountInfo = try #require(info.accounts.first)
        #expect(accountInfo.attachmentCacheSizeBytes == 5000) // Only downloaded
    }

    // MARK: - Warning Thresholds

    @Test("Per-account warning threshold at 2 GB")
    @MainActor
    func accountWarningThreshold() {
        let smallAccount = AccountStorageInfo(
            accountId: "small", email: "small@test.com", emailCount: 100,
            estimatedEmailSizeBytes: 1_000_000, attachmentCacheSizeBytes: 0,
            searchIndexSizeBytes: 100_000
        )
        #expect(smallAccount.exceedsWarningThreshold == false)

        let largeAccount = AccountStorageInfo(
            accountId: "large", email: "large@test.com", emailCount: 50000,
            estimatedEmailSizeBytes: 2_000_000_000, attachmentCacheSizeBytes: 500_000_000,
            searchIndexSizeBytes: 200_000_000
        )
        #expect(largeAccount.exceedsWarningThreshold == true)
    }

    @Test("App-wide warning threshold at 5 GB")
    @MainActor
    func appWarningThreshold() {
        let smallInfo = AppStorageInfo(accounts: [], aiModelSizeBytes: 1_000_000_000)
        #expect(smallInfo.exceedsWarningThreshold == false)

        let largeAccount = AccountStorageInfo(
            accountId: "a", email: "a@test.com", emailCount: 50000,
            estimatedEmailSizeBytes: 3_000_000_000, attachmentCacheSizeBytes: 1_000_000_000,
            searchIndexSizeBytes: 300_000_000
        )
        let largeInfo = AppStorageInfo(accounts: [largeAccount], aiModelSizeBytes: 1_500_000_000)
        #expect(largeInfo.exceedsWarningThreshold == true)
    }

    // MARK: - Byte Formatting

    @Test("formattedBytes produces readable output")
    func byteFormatting() {
        #expect(Int64(0).formattedBytes == "Zero KB")
        // Just verify it doesn't crash for various sizes
        _ = Int64(1024).formattedBytes
        _ = Int64(1_048_576).formattedBytes
        _ = Int64(1_073_741_824).formattedBytes
    }
}
