import Foundation

/// Talks to an OpenAI-compatible `/chat/completions` endpoint and streams the
/// answer back as plain text deltas.
public struct AIClient {
    private let configuration: AIConfiguration
    private let apiKey: String
    private let transport: AIStreamingTransport

    public init(
        configuration: AIConfiguration,
        apiKey: String,
        transport: AIStreamingTransport = URLSessionAIStreamTransport()
    ) {
        self.configuration = configuration
        self.apiKey = apiKey
        self.transport = transport
    }

    /// Sends the conversation and yields the assistant's text as it arrives.
    public func streamReply(_ history: [AIChatMessage]) async throws -> AsyncThrowingStream<String, Error> {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.missingKey
        }
        guard let url = configuration.chatCompletionsURL else {
            throw AIError.invalidURL
        }

        let request = AIStreamRequest(
            url: url,
            headers: headers,
            body: try body(for: history)
        )
        let payloads = try await transport.stream(request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await payload in payloads {
                        if let delta = try Self.delta(in: payload) {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request

    private var headers: [String: String] {
        var headers = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        ]
        if configuration.provider == .openRouter {
            // OpenRouter attributes usage by these two, and shows the app name
            // in its dashboard; both are optional but useful.
            headers["HTTP-Referer"] = "https://github.com/beretdt/goose-ide"
            headers["X-Title"] = "Goose IDE"
        }
        if configuration.provider == .gitHubModels {
            headers["Accept"] = "application/vnd.github+json"
            headers["X-GitHub-Api-Version"] = "2022-11-28"
        }
        return headers
    }

    private func body(for history: [AIChatMessage]) throws -> Data {
        var messages: [[String: String]] = []
        let system = configuration.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        messages.append(contentsOf: history.map { ["role": $0.role.rawValue, "content": $0.content] })

        let payload: [String: Any] = [
            "model": configuration.model,
            "messages": messages,
            "temperature": configuration.temperature,
            "max_tokens": configuration.maxTokens,
            "stream": true,
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - Stream

    /// Reads one server-sent event. A provider may report a failure inside the
    /// stream instead of in the status code, so that is checked too.
    private static func delta(in payload: String) throws -> String? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "erro do provedor"
            throw AIError.http(status: 0, message: message)
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first else {
            return nil
        }
        if let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return content
        }
        // Some providers send the whole message in a non-streaming chunk.
        if let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        return nil
    }
}
