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

                // TODO: Populate from SPM dependencies when they are added.
                Text("No third-party dependencies in V1.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Open Source Licenses")
    }
}

/// AI model licenses page.
/// Spec ref: Constitution LG-01, Foundation Section 10.1
struct AIModelLicensesView: View {
    var body: some View {
        List {
            Section("AI Model") {
                LabeledContent("Model", value: "PrivateMail AI v1")
                LabeledContent("License", value: "Apache 2.0")
                LabeledContent("Source", value: "huggingface.co/privatemail")
            }

            Section {
                Text("The AI model is licensed under the Apache License 2.0. You may use it for personal and commercial purposes. The model runs entirely on your device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AI Model Licenses")
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
