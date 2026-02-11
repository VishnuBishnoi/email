import Foundation
import SwiftData

/// Per-account storage breakdown.
///
/// Spec ref: Foundation Section 8.2, FR-SET-03
public struct AccountStorageInfo: Sendable, Identifiable {
    public let accountId: String
    public let email: String
    public let emailCount: Int
    public let estimatedEmailSizeBytes: Int64
    public let attachmentCacheSizeBytes: Int64
    public let searchIndexSizeBytes: Int64

    public var id: String { accountId }

    /// Total estimated storage for this account in bytes.
    public var totalBytes: Int64 {
        estimatedEmailSizeBytes + attachmentCacheSizeBytes + searchIndexSizeBytes
    }

    /// Whether this account exceeds the per-account warning threshold (2 GB).
    /// Spec ref: Foundation Section 8.2
    public var exceedsWarningThreshold: Bool {
        let thresholdBytes = Int64(AppConstants.accountStorageWarningGB * 1_073_741_824)
        return totalBytes > thresholdBytes
    }
}

/// App-wide storage information.
///
/// Spec ref: Foundation Section 8.2
public struct AppStorageInfo: Sendable {
    public let accounts: [AccountStorageInfo]
    public let aiModelSizeBytes: Int64

    /// Total storage across all accounts plus AI model.
    public var totalBytes: Int64 {
        accounts.reduce(into: Int64(0)) { $0 += $1.totalBytes } + aiModelSizeBytes
    }

    /// Whether total app storage exceeds the warning threshold (5 GB).
    /// Spec ref: Foundation Section 8.2
    public var exceedsWarningThreshold: Bool {
        let thresholdBytes = Int64(AppConstants.storageWarningThresholdGB * 1_073_741_824)
        return totalBytes > thresholdBytes
    }
}

/// Calculates per-account and total app storage usage.
///
/// Queries SwiftData for entity counts and size estimates. The actual disk
/// footprint of SwiftData is opaque, so this provides estimates based on
/// stored size fields (Email.sizeBytes, Attachment.sizeBytes).
///
/// Spec ref: FR-SET-03, Foundation Section 8.2, NFR-SET-05
@MainActor
public final class StorageCalculator {

    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Calculate storage breakdown for all accounts.
    /// - Returns: AppStorageInfo with per-account breakdown and AI model size.
    /// Single shared context for all operations. Safe because this class is @MainActor.
    private var context: ModelContext {
        modelContainer.mainContext
    }

    public func calculateStorage() async throws -> AppStorageInfo {

        // Fetch all accounts
        let accountDescriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.email)])
        let accounts = try context.fetch(accountDescriptor)

        var accountInfos: [AccountStorageInfo] = []

        for account in accounts {
            let info = try calculateAccountStorage(account: account, context: context)
            accountInfos.append(info)
        }

        // AI model size (check file on disk)
        let aiModelSize = calculateAIModelSize()

        return AppStorageInfo(accounts: accountInfos, aiModelSizeBytes: aiModelSize)
    }

    // MARK: - Private

    private func calculateAccountStorage(
        account: Account,
        context: ModelContext
    ) throws -> AccountStorageInfo {
        let accountId = account.id

        // Count emails and sum their sizes
        let emailDescriptor = FetchDescriptor<Email>(
            predicate: #Predicate { $0.accountId == accountId }
        )
        let emails = try context.fetch(emailDescriptor)
        let emailCount = emails.count
        let emailSizeBytes = emails.reduce(into: Int64(0)) { $0 += Int64($1.sizeBytes) }

        // Sum attachment cache sizes (downloaded attachments only)
        var totalAttachmentBytes: Int64 = 0
        for email in emails {
            for attachment in email.attachments {
                if attachment.isDownloaded {
                    totalAttachmentBytes += Int64(attachment.sizeBytes)
                }
            }
        }

        // Search index size estimate (approximate: ~10% of email body sizes)
        let searchIndexBytes = emailSizeBytes / 10

        return AccountStorageInfo(
            accountId: accountId,
            email: account.email,
            emailCount: emailCount,
            estimatedEmailSizeBytes: emailSizeBytes,
            attachmentCacheSizeBytes: totalAttachmentBytes,
            searchIndexSizeBytes: searchIndexBytes
        )
    }

    /// Calculate AI model file size on disk.
    /// Returns 0 if no model is downloaded.
    private func calculateAIModelSize() -> Int64 {
        // TODO: Check actual AI model file path when Data/AI/ layer is implemented.
        // For V1, return 0 (model download is stubbed).
        return 0
    }
}

// MARK: - Byte Formatting

extension Int64 {
    /// Formats bytes into a human-readable string (KB, MB, GB).
    public var formattedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}
