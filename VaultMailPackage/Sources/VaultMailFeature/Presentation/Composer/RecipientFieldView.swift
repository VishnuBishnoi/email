import SwiftUI

/// Token-based recipient input field with autocomplete.
///
/// Displays entered recipients as removable chips/tokens and shows
/// autocomplete suggestions from the local contact cache as the
/// user types. Invalid email addresses are highlighted with an
/// icon and color per NFR-COMP-03 (not color alone).
///
/// Spec ref: Email Composer FR-COMP-01, FR-COMP-04, NFR-COMP-03
struct RecipientFieldView: View {
    @Environment(ThemeProvider.self) private var theme

    let label: String
    @Binding var recipients: [RecipientToken]
    let queryContacts: QueryContactsUseCaseProtocol
    let accountIds: [String]

    @State private var inputText: String = ""
    @State private var suggestions: [ContactCacheEntry] = []
    @State private var showSuggestions = false
    @State private var suggestionTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            // Label + tokens + input
            HStack(alignment: .top, spacing: theme.spacing.xs) {
                Text(label)
                    .font(theme.typography.bodyMedium)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 36, alignment: .leading)
                    .padding(.top, theme.spacing.sm)

                tokenFlowContent
            }
            .padding(.horizontal, theme.spacing.lg)
            .padding(.vertical, theme.spacing.xs)

            // Autocomplete suggestions
            if showSuggestions && !suggestions.isEmpty {
                suggestionsList
            }

            Divider()
                .padding(.leading, 52)
        }
    }

    // MARK: - Token Flow

    @ViewBuilder
    private var tokenFlowContent: some View {
        // Simple wrap layout using vertical stacking
        FlowLayoutView {
            ForEach(recipients) { token in
                tokenChip(for: token)
            }

            TextField("", text: $inputText)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
                .autocorrectionDisabled()
                .focused($isInputFocused)
                .frame(minWidth: 100)
                .onSubmit {
                    commitCurrentInput()
                }
                .onChange(of: isInputFocused) { _, focused in
                    if !focused {
                        commitCurrentInput()
                    }
                }
                .onChange(of: inputText) { _, newValue in
                    // Auto-commit on comma or space separator
                    if newValue.hasSuffix(",") || newValue.hasSuffix(" ") {
                        let cleaned = String(newValue.dropLast())
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            inputText = cleaned
                            commitCurrentInput()
                            return
                        }
                    }
                    // Cancel any in-flight query and debounce by 250 ms
                    suggestionTask?.cancel()
                    suggestionTask = Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        await fetchSuggestions(prefix: newValue)
                    }
                }
                .accessibilityLabel("\(label) recipient field")
        }
    }

    // MARK: - Token Chip

    @ViewBuilder
    private func tokenChip(for token: RecipientToken) -> some View {
        HStack(spacing: theme.spacing.xs) {
            if !token.isValid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(theme.typography.labelSmall)
                    .foregroundStyle(theme.colors.textInverse)
            }
            Text(token.displayText)
                .font(theme.typography.bodyMedium)
                .lineLimit(1)
        }
        .padding(.horizontal, theme.spacing.sm)
        .padding(.vertical, theme.spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(token.isValid ? theme.colors.accentMuted : theme.colors.destructiveMuted)
        )
        .foregroundColor(token.isValid ? theme.colors.textPrimary : theme.colors.destructive)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(token.displayText), \(token.isValid ? "valid" : "invalid") email")
        .accessibilityRemoveTraits(.isButton)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Remove") {
            removeToken(token)
        }
        .onTapGesture {
            removeToken(token)
        }
    }

    // MARK: - Suggestions List

    @ViewBuilder
    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions, id: \.id) { contact in
                Button {
                    selectSuggestion(contact)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        if let name = contact.displayName, !name.isEmpty {
                            Text(name)
                                .font(theme.typography.bodyMedium)
                                .foregroundStyle(theme.colors.textPrimary)
                        }
                        Text(contact.emailAddress)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.spacing.lg)
                    .padding(.vertical, theme.spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if contact.id != suggestions.last?.id {
                    Divider()
                        .padding(.leading, theme.spacing.lg)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(theme.shapes.smallRect)
        .padding(.horizontal, 52)
        .padding(.bottom, theme.spacing.xs)
    }

    // MARK: - Actions

    private func commitCurrentInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let isValid = Self.isValidEmail(text)
        let token = RecipientToken(
            email: text,
            isValid: isValid
        )
        recipients.append(token)
        inputText = ""
        showSuggestions = false
    }

    private func removeToken(_ token: RecipientToken) {
        recipients.removeAll { $0.id == token.id }
    }

    private func selectSuggestion(_ contact: ContactCacheEntry) {
        let token = RecipientToken(
            email: contact.emailAddress,
            displayName: contact.displayName,
            isValid: true
        )
        // Don't add duplicate
        guard !recipients.contains(where: { $0.email.lowercased() == contact.emailAddress.lowercased() }) else {
            inputText = ""
            showSuggestions = false
            return
        }
        recipients.append(token)
        inputText = ""
        showSuggestions = false
    }

    private func fetchSuggestions(prefix: String) async {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else {
            suggestions = []
            showSuggestions = false
            return
        }
        do {
            let results = try await queryContacts.queryContacts(
                prefix: trimmed,
                accountIds: accountIds
            )
            // Filter out already-added recipients
            let existingEmails = Set(recipients.map { $0.email.lowercased() })
            suggestions = results.filter { !existingEmails.contains($0.emailAddress.lowercased()) }
            showSuggestions = !suggestions.isEmpty
        } catch {
            suggestions = []
            showSuggestions = false
        }
    }

    // MARK: - Validation

    /// Validates an email address format.
    static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Flow Layout

/// Simple flow layout that wraps children horizontally.
struct FlowLayoutView: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var offsets: [CGPoint]
        var sizes: [CGSize]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalHeight = currentY + lineHeight
        }

        return LayoutResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            offsets: offsets,
            sizes: sizes
        )
    }
}

// MARK: - Previews

#Preview("Empty") {
    RecipientFieldView(
        label: "To",
        recipients: .constant([]),
        queryContacts: PreviewQueryContactsUseCase(),
        accountIds: ["acc1"]
    )
    .environment(ThemeProvider())
}

#Preview("With Tokens") {
    RecipientFieldView(
        label: "To",
        recipients: .constant([
            RecipientToken(email: "alice@example.com", displayName: "Alice Smith", isValid: true),
            RecipientToken(email: "bob@example.com", isValid: true),
            RecipientToken(email: "invalid-email", isValid: false)
        ]),
        queryContacts: PreviewQueryContactsUseCase(),
        accountIds: ["acc1"]
    )
    .environment(ThemeProvider())
}

/// Preview-only stub.
@MainActor
private final class PreviewQueryContactsUseCase: QueryContactsUseCaseProtocol {
    func queryContacts(prefix: String, accountIds: [String]) async throws -> [ContactCacheEntry] {
        return []
    }
}
