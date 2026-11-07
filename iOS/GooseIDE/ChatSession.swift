import Foundation
import GooseAI

/// The chat with the code agent: the messages, the streaming call, and the
/// code the agent is writing right now.
///
/// Not actor-isolated, because `@StateObject` builds it in a non-isolated
/// property initializer. Every mutation hops to the main actor explicitly.
final class ChatSession: ObservableObject {
    @Published var configuration: AIConfiguration
    @Published private(set) var messages: [AIChatMessage] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var errorMessage: String?

    /// Whether the current provider has a key, cached so a view body does not
    /// read the keychain on every redraw.
    @Published private(set) var hasKey: Bool

    /// The code inside the reply's ```goose block, updated as it arrives, so
    /// the editor can show the agent editing it live.
    @Published private(set) var liveEdit: String?
    @Published private(set) var liveEditClosed = false

    private var streamTask: Task<Void, Never>?

    init() {
        let configuration = AIConfigurationStore.load()
        self.configuration = configuration
        hasKey = !(AIKeyStore.load(for: configuration.provider) ?? "").isEmpty
    }

    private var key: String {
        AIKeyStore.load(for: configuration.provider) ?? ""
    }

    func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        AIKeyStore.save(trimmed, for: configuration.provider)
        hasKey = !trimmed.isEmpty
    }

    func update(_ configuration: AIConfiguration) {
        self.configuration = configuration
        AIConfigurationStore.save(configuration)
        hasKey = !(AIKeyStore.load(for: configuration.provider) ?? "").isEmpty
    }

    @MainActor
    func clearConversation() {
        streamTask?.cancel()
        streamTask = nil
        messages = []
        liveEdit = nil
        liveEditClosed = false
        errorMessage = nil
        isStreaming = false
    }

    // MARK: - Sending

    /// Sends the prompt with the current program as context. The program is
    /// not stored in the transcript, so later turns do not pile up copies of
    /// it; it is attached to the outgoing message only.
    @MainActor
    func send(_ prompt: String, program: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        let outgoing = contextPrompt(text, program: program)
        let history = messages + [AIChatMessage(role: .user, content: outgoing)]

        messages.append(AIChatMessage(role: .user, content: text))
        let placeholder = AIChatMessage(role: .assistant, content: "")
        messages.append(placeholder)
        errorMessage = nil
        liveEdit = nil
        liveEditClosed = false
        isStreaming = true

        let client = AIClient(configuration: configuration, apiKey: key)
        streamTask = Task { [weak self] in
            guard let self else { return }

            do {
                let stream = try await client.streamReply(history)
                for try await chunk in stream {
                    try Task.checkCancellation()
                    await self.append(chunk, to: placeholder.id)
                }
            } catch is CancellationError {
                // The user stopped the answer; what arrived stays.
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }

            await MainActor.run {
                self.isStreaming = false
                self.liveEditClosed = self.liveEdit != nil
            }
        }
    }

    @MainActor
    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        liveEditClosed = liveEdit != nil
    }

    // MARK: - Streaming helpers

    private func append(_ chunk: String, to id: UUID) async {
        await MainActor.run {
            guard let index = self.messages.firstIndex(where: { $0.id == id }) else { return }
            self.messages[index].content += chunk

            if self.configuration.applyEditsLive,
               let block = AIEditExtractor.gooseBlock(in: self.messages[index].content) {
                self.liveEdit = block.code
                self.liveEditClosed = block.closed
            }
        }
    }

    /// The program goes in the first user turn of each request, wrapped in a
    /// tag the system prompt explains nothing about — the model reads it as
    /// context, which is what it is.
    private func contextPrompt(_ question: String, program: String) -> String {
        guard !program.isEmpty else { return question }
        return """
        <programa_atual>
        ```goose
        \(program)
        ```
        </programa_atual>

        \(question)
        """
    }
}
