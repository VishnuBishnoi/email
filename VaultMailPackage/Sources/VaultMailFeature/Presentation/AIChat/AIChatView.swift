import SwiftUI

/// On-device AI chat assistant for email-related conversations.
///
/// Uses `AIEngineResolver` to resolve the best available local LLM engine,
/// then streams token-by-token responses via `engine.generate()`. All processing
/// is on-device — no data leaves the device.
///
/// MV pattern: view state managed via @State, engine injected as `let` property.
///
/// Spec ref: FR-AI-CHAT
struct AIChatView: View {

    let engineResolver: AIEngineResolver

    // MARK: - State

    @State private var chatModel = ChatModel()
    @State private var inputText = ""
    @State private var generationTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if chatModel.messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            Divider()
            inputBar
        }
        .navigationTitle("AI Assistant")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await checkEngineAvailability()
        }
        .onDisappear {
            generationTask?.cancel()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.purple.opacity(0.6))
                .accessibilityHidden(true)

            Text("AI Assistant")
                .font(.title2.bold())

            Text("Ask me anything about your emails.\nI run entirely on your device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !chatModel.engineAvailable {
                Label(
                    "Download an AI model in Settings to get started.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .padding(.horizontal, 24)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI Assistant. Ask me anything about your emails.")
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chatModel.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .onChange(of: chatModel.messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: chatModel.lastMessageText) {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = chatModel.messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask about your emails...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                .disabled(chatModel.isGenerating)

            if chatModel.isGenerating {
                Button {
                    stopGeneration()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("Stop generating")
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? .blue : .gray.opacity(0.5))
                }
                .disabled(!canSend)
                .accessibilityLabel("Send message")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Computed

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatModel.isGenerating
    }

    // MARK: - Actions

    private func checkEngineAvailability() async {
        let engine = await engineResolver.resolveGenerativeEngine()
        let available = await engine.isAvailable()
        chatModel.engineAvailable = available
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Add user message
        chatModel.addMessage(role: .user, text: text)
        inputText = ""

        // Add placeholder assistant message
        let assistantId = chatModel.addMessage(role: .assistant, text: "")
        chatModel.isGenerating = true

        generationTask = Task {
            let engine = await engineResolver.resolveGenerativeEngine()

            let available = await engine.isAvailable()
            guard available else {
                await MainActor.run {
                    chatModel.updateMessage(id: assistantId, text: "AI model not available. Please download a model in Settings → AI Features.")
                    chatModel.engineAvailable = false
                    chatModel.isGenerating = false
                }
                return
            }

            // Build conversation history for the prompt.
            // Drop the last 2 messages (placeholder assistant + new user) since
            // PromptTemplates.chat() appends the userMessage itself.
            let history: [(role: String, content: String)] = await MainActor.run {
                chatModel.messages.dropLast(2).map { msg in
                    (role: msg.role == .user ? "User" : "Assistant", content: msg.text)
                }
            }
            let prompt = PromptTemplates.chat(
                conversationHistory: history,
                userMessage: text
            )

            let stream = await engine.generate(prompt: prompt, maxTokens: 1024)
            for await token in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    chatModel.appendToMessage(id: assistantId, token: token)
                }
            }

            // If empty response (model returned nothing), show fallback
            await MainActor.run {
                let currentText = chatModel.messageText(for: assistantId)
                if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chatModel.updateMessage(id: assistantId, text: "I couldn't generate a response. Please try again.")
                }
                chatModel.isGenerating = false
            }
        }
    }

    private func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        chatModel.isGenerating = false

        // If the assistant message is empty after cancellation, add a note
        if let last = chatModel.messages.last, last.role == .assistant,
           last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chatModel.updateMessage(id: last.id, text: "(Generation stopped)")
        }
    }
}

// MARK: - Chat Model (@Observable)

/// Observable model that holds chat state. Using @Observable ensures
/// SwiftUI properly tracks all mutations including array element updates.
@Observable
@MainActor
final class ChatModel {
    var messages: [ChatMessage] = []
    var isGenerating = false
    var engineAvailable = true

    /// Text of the last message — used by `.onChange` to detect streaming updates.
    var lastMessageText: String {
        messages.last?.text ?? ""
    }

    @discardableResult
    func addMessage(role: ChatMessage.Role, text: String) -> UUID {
        let message = ChatMessage(role: role, text: text)
        messages.append(message)
        return message.id
    }

    func updateMessage(id: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
    }

    func appendToMessage(id: UUID, token: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += token
    }

    func messageText(for id: UUID) -> String {
        messages.first(where: { $0.id == id })?.text ?? ""
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var text: String
    let timestamp = Date()

    enum Role: Equatable {
        case user
        case assistant
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    private var isEmptyAssistant: Bool {
        message.role == .assistant && message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if isEmptyAssistant {
                    // Typing indicator while waiting for tokens
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityLabel("AI is thinking")
                } else {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(message.role == .user ? .white : .primary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                message.role == .user
                    ? Color.blue
                    : Color.secondary.opacity(0.15),
                in: RoundedRectangle(cornerRadius: 16)
            )

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "You" : "AI"): \(isEmptyAssistant ? "Thinking" : message.text)")
    }
}
