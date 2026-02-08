import SwiftUI

/// AI model management settings.
///
/// Displays model status, download/delete actions, and model details.
/// V1: Download is stubbed (simulated progress).
///
/// Spec ref: FR-SET-04, Proposal Section 3.4.1, Foundation Section 11
struct AIModelSettingsView: View {
    @State private var downloadState: AIDownloadState = .notDownloaded
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            // Model status
            Section("Status") {
                HStack {
                    Text("AI Model")
                    Spacer()
                    statusBadge
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("AI Model status: \(statusLabel)")
            }

            // Model details
            Section("Details") {
                LabeledContent("Model", value: "PrivateMail AI v1")
                LabeledContent("Size", value: "~1.5 GB")
                LabeledContent("Source", value: "huggingface.co/privatemail")
                LabeledContent("License", value: "Apache 2.0")
            }

            // Actions
            Section {
                switch downloadState {
                case .notDownloaded:
                    Button("Download AI Model") {
                        startDownload()
                    }

                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progress)
                        HStack {
                            Text("Downloading… \(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Cancel", role: .cancel) {
                                downloadState = .notDownloaded
                            }
                            .font(.caption)
                        }
                    }

                case .verifying:
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Verifying integrity…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                case .downloaded:
                    Button("Delete AI Model", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .alert("Delete AI Model", isPresented: $showDeleteConfirmation) {
                        Button("Delete", role: .destructive) {
                            downloadState = .notDownloaded
                            // TODO: Delete actual model file when Data/AI/ layer is built.
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Deleting the AI model will disable smart categories, smart reply, and thread summarization.")
                    }

                case .failed(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                        Button("Retry") {
                            startDownload()
                        }
                    }
                }
            }
        }
        .navigationTitle("AI Model")
    }

    // MARK: - Status Display

    @ViewBuilder
    private var statusBadge: some View {
        switch downloadState {
        case .notDownloaded:
            Text("Not Downloaded")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .downloading:
            Text("Downloading")
                .font(.callout)
                .foregroundStyle(.orange)
        case .verifying:
            Text("Verifying")
                .font(.callout)
                .foregroundStyle(.orange)
        case .downloaded:
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    private var statusLabel: String {
        switch downloadState {
        case .notDownloaded: "Not downloaded"
        case .downloading: "Downloading"
        case .verifying: "Verifying"
        case .downloaded: "Downloaded"
        case .failed: "Failed"
        }
    }

    // MARK: - Actions

    /// PARTIAL SCOPE — V1 STUB: Simulates download.
    /// Blocked on Data/AI/ layer. Real implementation MUST provide:
    /// - HTTPS download with HTTP Range resume support (FR-SET-04)
    /// - Post-download SHA-256 integrity verification
    /// - Corrupted file cleanup on checksum mismatch
    /// See OnboardingAIModelStep for identical stub logic.
    private func startDownload() {
        downloadState = .downloading(progress: 0)
        Task {
            for i in 1...10 {
                try? await Task.sleep(for: .milliseconds(300))
                if case .notDownloaded = downloadState { return }
                downloadState = .downloading(progress: Double(i) / 10.0)
            }
            downloadState = .verifying
            try? await Task.sleep(for: .milliseconds(500))
            downloadState = .downloaded
        }
    }
}

#Preview {
    NavigationStack {
        AIModelSettingsView()
    }
}
