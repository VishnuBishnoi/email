import SwiftUI

/// Onboarding Step 4: AI model download with informed consent and storage disclosure.
///
/// Displays model source URL, file size, and license before download begins
/// (per Proposal Section 3.4.1). Includes a skip option and storage disclosure
/// per Constitution TC-06.
///
/// **V1 Note**: AI model download is stubbed (simulated progress). Real download
/// and SHA-256 verification will be implemented when Data/AI/ layer is built.
///
/// Spec ref: FR-OB-01 step 4, Proposal Section 3.4.1, Constitution TC-06
struct OnboardingAIModelStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var downloadState: AIDownloadState = .notDownloaded

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cpu.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("AI Features")
                .font(.title2.bold())

            Text("Download the AI model for smart categories, reply suggestions, and email summarization.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Model info card (Proposal Section 3.4.1)
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Model", value: "PrivateMail AI v1")
                    LabeledContent("Size", value: "~1.5 GB")
                    LabeledContent("License", value: "Apache 2.0")
                    LabeledContent("Source", value: "huggingface.co/privatemail")
                }
                .font(.callout)
            }
            .padding(.horizontal)

            // Storage disclosure (Constitution TC-06)
            Text("Syncing your email typically uses 500 MB – 2 GB of storage on this device, depending on email volume. AI features require an additional 500 MB – 2 GB.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Download state UI
            downloadStateView
                .padding(.horizontal)

            Spacer()

            // Skip option (always visible)
            Button("Skip — the app works without AI features.") {
                cancelDownloadIfNeeded()
                onSkip()
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            // Next button (only after download completes)
            if case .downloaded = downloadState {
                Button("Next") {
                    onNext()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }

    // MARK: - Download State View

    @ViewBuilder
    private var downloadStateView: some View {
        switch downloadState {
        case .notDownloaded:
            Button("Download AI Model") {
                startDownload()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .downloading(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress) {
                    Text("Downloading…")
                        .font(.callout)
                }
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel") {
                    downloadState = .notDownloaded
                }
                .font(.callout)
            }

        case .verifying:
            VStack(spacing: 8) {
                ProgressView()
                Text("Verifying integrity…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .downloaded:
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(.green)

        case .failed(let message):
            VStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                Button("Retry") {
                    startDownload()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Actions

    /// PARTIAL SCOPE — V1 STUB: Simulates AI model download with progress.
    /// Blocked on Data/AI/ layer (not yet built). Real implementation MUST:
    /// - Use HTTPS with HTTP Range headers for resumable downloads (FR-SET-04)
    /// - Perform SHA-256 integrity verification post-download (FR-OB-01 step 4)
    /// - Clean up corrupted files on checksum mismatch
    /// Tracked in: AI Model Management epic
    private func startDownload() {
        downloadState = .downloading(progress: 0)
        Task {
            for i in 1...10 {
                try? await Task.sleep(for: .milliseconds(300))
                if case .notDownloaded = downloadState { return } // Cancelled
                downloadState = .downloading(progress: Double(i) / 10.0)
            }
            downloadState = .verifying
            try? await Task.sleep(for: .milliseconds(500))
            downloadState = .downloaded
        }
    }

    private func cancelDownloadIfNeeded() {
        if case .downloading = downloadState {
            downloadState = .notDownloaded
        }
    }
}

/// Download state for AI model.
enum AIDownloadState {
    case notDownloaded
    case downloading(progress: Double)
    case verifying
    case downloaded
    case failed(String)
}

#Preview("Not Downloaded") {
    OnboardingAIModelStep(onNext: {}, onSkip: {})
}
