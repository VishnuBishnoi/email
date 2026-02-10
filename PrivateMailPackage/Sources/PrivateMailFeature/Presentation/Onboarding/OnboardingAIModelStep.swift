import SwiftUI

/// Onboarding Step 4: AI model download with informed consent and storage disclosure.
///
/// Displays model source URL, file size, and license before download begins
/// (per Proposal Section 3.4.1). Includes a skip option and storage disclosure
/// per Constitution TC-06.
///
/// Wired to real `ModelManager` for download and SHA-256 verification.
///
/// Spec ref: FR-OB-01 step 4, Proposal Section 3.4.1, Constitution TC-06, AC-A-08
struct OnboardingAIModelStep: View {
    let modelManager: ModelManager
    var aiEngineResolver: AIEngineResolver?
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var downloadState: AIDownloadState = .notDownloaded
    @State private var recommendedModel: ModelManager.ModelInfo?
    @State private var downloadProgress: Double = 0

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
            if let model = recommendedModel {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Model", value: model.name)
                        LabeledContent("Size", value: model.formattedSize)
                        LabeledContent("License", value: model.license)
                        LabeledContent("Source", value: model.downloadURL.host ?? "Unknown")
                    }
                    .font(.callout)
                }
                .padding(.horizontal)
            }

            // Storage disclosure (Constitution TC-06)
            Text("Syncing your email typically uses 500 MB \u{2013} 2 GB of storage on this device, depending on email volume. AI features require an additional \(recommendedModel?.formattedSize ?? "500 MB \u{2013} 1 GB").")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Download state UI
            downloadStateView
                .padding(.horizontal)

            Spacer()

            // Skip option (always visible)
            Button("Skip \u{2014} the app works without AI features.") {
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
        .task {
            await loadRecommendedModel()
        }
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
                    Text("Downloading\u{2026}")
                        .font(.callout)
                }
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel") {
                    cancelDownloadIfNeeded()
                }
                .font(.callout)
            }

        case .verifying:
            VStack(spacing: 8) {
                ProgressView()
                Text("Verifying integrity\u{2026}")
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

    private func loadRecommendedModel() async {
        let resolver = AIEngineResolver(modelManager: modelManager)
        let recommendedID = resolver.recommendedModelID()
        let models = await modelManager.availableModels()

        if let model = models.first(where: { $0.id == recommendedID }) {
            recommendedModel = model.info
            if model.status == .downloaded {
                downloadState = .downloaded
            }
        } else {
            recommendedModel = models.first?.info
        }
    }

    /// Download the recommended AI model with real progress tracking.
    ///
    /// Uses ModelManager for HTTPS download with HTTP Range resume support,
    /// SHA-256 integrity verification, and corrupt file cleanup.
    private func startDownload() {
        guard let model = recommendedModel else { return }

        downloadState = .downloading(progress: 0)
        downloadProgress = 0

        Task {
            do {
                try await modelManager.downloadModel(id: model.id) { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                        self.downloadState = .downloading(progress: progress)
                    }
                }
                await aiEngineResolver?.invalidateCache()
                downloadState = .downloaded
            } catch {
                if case AIEngineError.downloadCancelled = error {
                    downloadState = .notDownloaded
                } else {
                    downloadState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func cancelDownloadIfNeeded() {
        if case .downloading = downloadState {
            if let model = recommendedModel {
                Task {
                    await modelManager.cancelDownload(id: model.id)
                }
            }
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
    OnboardingAIModelStep(modelManager: ModelManager(), onNext: {}, onSkip: {})
}
