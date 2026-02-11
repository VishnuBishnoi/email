import SwiftUI
import SwiftData

/// Storage usage breakdown, clear cache, and wipe all data.
///
/// Displays per-account storage breakdown with warnings for
/// accounts exceeding 2 GB and total storage exceeding 5 GB.
///
/// Spec ref: FR-SET-03, Foundation Section 8.2, NFR-SET-05
struct StorageSettingsView: View {
    let manageAccounts: ManageAccountsUseCaseProtocol

    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var storageInfo: AppStorageInfo?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showWipeConfirmation = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Calculating storage…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await loadStorage() }
                    }
                }
            } else if let info = storageInfo {
                // Total storage
                Section("Total") {
                    LabeledContent("Total Storage", value: info.totalBytes.formattedBytes)
                    if info.aiModelSizeBytes > 0 {
                        LabeledContent("AI Model", value: info.aiModelSizeBytes.formattedBytes)
                    }
                    if info.exceedsWarningThreshold {
                        Label("Total storage exceeds 5 GB", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }

                // Per-account breakdown
                ForEach(info.accounts) { accountInfo in
                    Section(accountInfo.email) {
                        LabeledContent("Emails (\(accountInfo.emailCount))", value: accountInfo.estimatedEmailSizeBytes.formattedBytes)
                        LabeledContent("Attachments", value: accountInfo.attachmentCacheSizeBytes.formattedBytes)
                        LabeledContent("Search Index", value: accountInfo.searchIndexSizeBytes.formattedBytes)
                        LabeledContent("Total", value: accountInfo.totalBytes.formattedBytes)
                            .fontWeight(.medium)

                        if accountInfo.exceedsWarningThreshold {
                            Label("Account storage exceeds 2 GB", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.callout)
                        }
                    }
                }

                // Empty state
                if info.accounts.isEmpty {
                    Section {
                        Text("No accounts configured.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Storage Usage")
        .task { await loadStorage() }
    }

    // MARK: - Actions

    private func loadStorage() async {
        isLoading = true
        errorMessage = nil
        do {
            let container = modelContext.container
            let calculator = StorageCalculator(modelContainer: container)
            storageInfo = try await calculator.calculateStorage()
        } catch {
            errorMessage = "Unable to calculate storage"
        }
        isLoading = false
    }
}
