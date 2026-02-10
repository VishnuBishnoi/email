import SwiftUI

/// About section: version, privacy policy, licenses.
///
/// Spec ref: FR-SET-05, Constitution LG-01, LG-02, Foundation Section 10.1, 10.3
struct AboutView: View {
    var body: some View {
        List {
            // App version and build (FR-SET-05)
            Section {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
            }

            // Legal & Licenses
            Section("Legal") {
                NavigationLink("Privacy Policy") {
                    PrivacyPolicyView()
                }

                NavigationLink("Open Source Licenses") {
                    OpenSourceLicensesView()
                }

                NavigationLink("AI Model Licenses") {
                    AIModelLicensesView()
                }
            }
        }
        .navigationTitle("About")
    }

    // MARK: - Version Info

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

// MARK: - Sub-Views

/// In-app privacy policy display.
/// Spec ref: Constitution LG-02, Foundation Section 10.3
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.title2.bold())

                Text("PrivateMail is designed with privacy as a core principle. Your email data is stored exclusively on your device and is never transmitted to our servers.")
                    .font(.body)

                Text("Data Collection")
                    .font(.headline)
                Text("PrivateMail does not collect, store, or transmit any user data to external servers. All email data, including messages, attachments, and account credentials, remain on your device.")
                    .font(.body)

                Text("AI Processing")
                    .font(.headline)
                Text("All AI features (smart categories, reply suggestions, summarization) run entirely on your device using a locally downloaded model. No email content is sent to cloud AI services.")
                    .font(.body)

                // Full privacy policy URL (Constitution LG-02)
                // TODO: Replace with actual hosted privacy policy URL before App Store submission.
                if let url = URL(string: "https://privatemail.app/privacy") {
                    Link("View Full Privacy Policy", destination: url)
                        .font(.callout)
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
    }
}

/// Open source licenses page.
/// Spec ref: FR-SET-05
struct OpenSourceLicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Open Source Licenses")
                    .font(.title2.bold())

                Text("PrivateMail uses the following open source software:")
                    .font(.body)
                    .foregroundStyle(.secondary)

                LicenseRow(
                    name: "llama.cpp (via llama.swift)",
                    license: "MIT",
                    url: "https://github.com/ggerganov/llama.cpp"
                )
            }
            .padding()
        }
        .navigationTitle("Open Source Licenses")
    }
}

/// AI model licenses page showing real model metadata from ModelManager.
/// Spec ref: Constitution LG-01, Foundation Section 10.1
struct AIModelLicensesView: View {
    private let models = ModelManager.availableModelInfos

    var body: some View {
        List {
            ForEach(models) { model in
                Section(model.name) {
                    LabeledContent("Model", value: model.name)
                    LabeledContent("File", value: model.fileName)
                    LabeledContent("Size", value: model.formattedSize)
                    LabeledContent("License", value: model.license)
                    LabeledContent("Source", value: model.downloadURL.host ?? "Unknown")
                    LabeledContent("Min RAM", value: "\(model.minRAMGB) GB")
                }
            }

            Section {
                Text("All AI models are licensed under the Apache License 2.0. You may use them for personal and commercial purposes. Models run entirely on your device — no email content is sent to external servers.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AI Model Licenses")
    }
}

// MARK: - License Row

/// Reusable row for displaying an open-source dependency.
private struct LicenseRow: View {
    let name: String
    let license: String
    let url: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.body)
            Text(license)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let link = URL(string: url) {
                Link(url, destination: link)
                    .font(.caption)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
