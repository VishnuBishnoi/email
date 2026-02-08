import SwiftUI

struct RecipientFieldView: View {
    let title: String
    @Binding var addresses: [String]
    let invalidAddresses: Set<String>
    let querySuggestions: @Sendable (String) async -> [ContactSuggestion]

    @State private var input = ""
    @State private var suggestions: [ContactSuggestion] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(addresses, id: \.self) { address in
                            recipientChip(address)
                        }
                    }
                }

                TextField("Add recipient", text: $input)
                    .textFieldStyle(.plain)
                    .onSubmit { commitInput() }
                    .onChange(of: input) {
                        if input.contains(",") || input.contains(";") {
                            commitInput()
                        } else {
                            Task { await loadSuggestions(for: input) }
                        }
                    }
                    .accessibilityLabel("\(title) recipient input")

                if !suggestions.isEmpty {
                    suggestionsList
                }
            }
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions, id: \.emailAddress) { suggestion in
                Button {
                    addAddress(suggestion.emailAddress)
                    input = ""
                    suggestions = []
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            if let name = suggestion.displayName, !name.isEmpty {
                                Text(name)
                                    .font(.subheadline)
                            }
                            Text(suggestion.emailAddress)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.secondary.opacity(0.08))
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recipient suggestions")
    }

    private func recipientChip(_ address: String) -> some View {
        let isInvalid = invalidAddresses.contains(address)

        return HStack(spacing: 6) {
            if isInvalid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text(address)
                .lineLimit(1)
            Button {
                addresses.removeAll { $0 == address }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(address)")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isInvalid ? Color.red.opacity(0.12) : Color.secondary.opacity(0.12))
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isInvalid ? "Invalid recipient \(address)" : "Recipient \(address)")
    }

    private func commitInput() {
        let raw = input
        input = ""
        suggestions = []

        let candidates = raw
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for value in candidates {
            addAddress(value)
        }
    }

    private func addAddress(_ value: String) {
        guard !addresses.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        addresses.append(value)
    }

    @MainActor
    private func loadSuggestions(for query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            return
        }

        let fetched = await querySuggestions(trimmed)
        suggestions = fetched.filter { suggestion in
            !addresses.contains(where: { $0.caseInsensitiveCompare(suggestion.emailAddress) == .orderedSame })
        }
    }
}

#Preview {
    @Previewable @State var addresses = ["alice@example.com", "bob@example.com"]
    return RecipientFieldView(
        title: "To",
        addresses: $addresses,
        invalidAddresses: ["bob@example.com"],
        querySuggestions: { _ in
            [
                ContactSuggestion(emailAddress: "carol@example.com", displayName: "Carol", frequency: 12, lastSeenDate: .now),
                ContactSuggestion(emailAddress: "dave@example.com", displayName: "Dave", frequency: 8, lastSeenDate: .now)
            ]
        }
    )
    .padding()
}
