import SwiftUI

/// AI model management settings.
///
/// Displays available GGUF models with download status, download/delete actions,
/// and model details including size, license, and source URL.
///
/// Wired to real `ModelManager` for download, verification, and storage tracking.
///
/// Spec ref: FR-SET-04, Proposal Section 3.4.1, Constitution LG-01, AC-A-03
struct AIModelSettingsView: View {
    let modelManager: ModelManager
    var aiEngineResolver: AIEngineResolver?

    @State private var models: [ModelManager.ModelState] = []
    @State private var downloadingModelID: String?
    @State private var downloadProgress: Double = 0
    @State private var storageUsage: UInt64 = 0
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: String?

    var body: some View {
        List {
            // Storage usage
            Section("Storage") {
                LabeledContent("AI Models", value: formattedStorageUsage)
                    .accessibilityLabel("AI model storage usage: \(formattedStorageUsage)")
            }

            // Available models
            ForEach(models) { model in
                Section(model.info.name) {
                    LabeledContent("Size", value: model.info.formattedSize)
                    LabeledContent("License", value: model.info.license)
                    LabeledContent("Source", value: model.info.downloadURL.host ?? "Unknown")
                    LabeledContent("Min RAM", value: "\(model.info.minRAMGB) GB")

                    modelActionView(for: model)
                }
            }
        }
        .navigationTitle("AI Models")
        .task {
            await loadModels()
        }
    }

    // MARK: - Model Action View

    @ViewBuilder
    private func modelActionView(for model: ModelManager.ModelState) -> some View {
        switch model.status {
        case .notDownloaded:
            if downloadingModelID == model.id {
                downloadProgressView
            } else {
                Button("Download") {
                    startDownload(modelID: model.id)
                }
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
                        cancelDownload(modelID: model.id)
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
            Button("Delete", role: .destructive) {
                modelToDelete = model.id
                showDeleteConfirmation = true
            }
            .alert("Delete \(model.info.name)?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let id = modelToDelete {
                        deleteModel(modelID: id)
                    }
                }
                Button("Cancel", role: .cancel) {
                    modelToDelete = nil
                }
            } message: {
                Text("Deleting this model will disable AI features that require it. You can re-download it later.")
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                Button("Retry") {
                    startDownload(modelID: model.id)
                }
            }
        }
    }

    @ViewBuilder
    private var downloadProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: downloadProgress)
            HStack {
                Text("Downloading… \(Int(downloadProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) {
                    if let id = downloadingModelID {
                        cancelDownload(modelID: id)
                    }
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Helpers

    private var formattedStorageUsage: String {
        ByteCountFormatter.string(fromByteCount: Int64(storageUsage), countStyle: .file)
    }

    // MARK: - Actions

    private func loadModels() async {
        models = await modelManager.availableModels()
        storageUsage = await modelManager.storageUsage()
    }

    private func startDownload(modelID: String) {
        downloadingModelID = modelID
        downloadProgress = 0

        Task {
            do {
                try await modelManager.downloadModel(id: modelID) { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }
                downloadingModelID = nil
                await aiEngineResolver?.invalidateCache()
                await loadModels()
            } catch {
                downloadingModelID = nil
                await loadModels()
            }
        }
    }

    private func cancelDownload(modelID: String) {
        Task {
            await modelManager.cancelDownload(id: modelID)
            downloadingModelID = nil
            await loadModels()
        }
    }

    private func deleteModel(modelID: String) {
        Task {
            try? await modelManager.deleteModel(id: modelID)
            modelToDelete = nil
            await aiEngineResolver?.invalidateCache()
            await loadModels()
        }
    }
}

#Preview {
    NavigationStack {
        AIModelSettingsView(modelManager: ModelManager())
    }
}
