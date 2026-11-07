import XCTest
@testable import GooseAI

/// Emits scripted payloads, and records the request the client built.
private final class FakeStreamTransport: AIStreamingTransport, @unchecked Sendable {
    var payloads: [String] = []
    var failure: Error?
    private(set) var requests: [AIStreamRequest] = []

    func stream(_ request: AIStreamRequest) async throws -> AsyncThrowingStream<String, Error> {
        requests.append(request)
        if let failure { throw failure }

        let payloads = self.payloads
        return AsyncThrowingStream { continuation in
            for payload in payloads {
                continuation.yield(payload)
            }
            continuation.finish()
        }
    }
}

private func delta(_ text: String) -> String {
    let escaped = text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return #"{"choices":[{"delta":{"content":"\#(escaped)"}}]}"#
}

private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
    var result = ""
    for try await chunk in stream {
        result += chunk
    }
    return result
}

final class AIClientTests: XCTestCase {
    private let history = [
        AIChatMessage(role: .user, content: "faça um fib"),
    ]

    func testOpenRouterRequestShape() async throws {
        let transport = FakeStreamTransport()
        transport.payloads = [delta("ok")]
        let configuration = AIConfiguration(provider: .openRouter, model: "anthropic/claude-sonnet-4")
        let client = AIClient(configuration: configuration, apiKey: "sk-or-1", transport: transport)

        let text = try await collect(try await client.streamReply(history))

        XCTAssertEqual(text, "ok")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer sk-or-1")
        XCTAssertEqual(request.headers["X-Title"], "Goose IDE")
        XCTAssertEqual(request.headers["HTTP-Referer"], "https://github.com/beretdt/goose-ide")

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "anthropic/claude-sonnet-4")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["temperature"] as? Double, 0.2)

        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertEqual(messages.last?["role"], "user")
        XCTAssertEqual(messages.last?["content"], "faça um fib")
    }

    func testGitHubModelsUsesItsOwnURLAndVersionHeader() async throws {
        let transport = FakeStreamTransport()
        transport.payloads = [delta("x")]
        let configuration = AIConfiguration(
            provider: .gitHubModels,
            model: "openai/gpt-4o",
            baseURL: AIProvider.gitHubModels.defaultBaseURL
        )
        let client = AIClient(configuration: configuration, apiKey: "github_pat_x", transport: transport)

        _ = try await collect(try await client.streamReply(history))

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://models.github.ai/inference/chat/completions")
        XCTAssertEqual(request.headers["X-GitHub-Api-Version"], "2022-11-28")
        XCTAssertEqual(request.headers["X-Title"], nil)
    }

    func testCustomBaseURLKeepsTrailingSlashUnderControl() async throws {
        let transport = FakeStreamTransport()
        transport.payloads = []
        let configuration = AIConfiguration(
            provider: .custom,
            model: "llama3",
            baseURL: "http://192.168.0.10:11434/v1/"
        )
        let client = AIClient(configuration: configuration, apiKey: "k", transport: transport)

        _ = try await collect(try await client.streamReply(history))

        XCTAssertEqual(
            transport.requests.first?.url.absoluteString,
            "http://192.168.0.10:11434/v1/chat/completions"
        )
    }

    func testEmptySystemPromptIsOmitted() async throws {
        let transport = FakeStreamTransport()
        transport.payloads = []
        var configuration = AIConfiguration()
        configuration.systemPrompt = "   "
        let client = AIClient(configuration: configuration, apiKey: "k", transport: transport)

        _ = try await collect(try await client.streamReply(history))

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(transport.requests.first).body) as? [String: Any]
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"], "user")
    }

    func testDeltasAreJoinedInOrder() async throws {
        let transport = FakeStreamTransport()
        transport.payloads = [delta("fn "), delta("main"), delta("() {}")]
        let client = AIClient(configuration: AIConfiguration(), apiKey: "k", transport: transport)

        let text = try await collect(try await client.streamReply(history))

        XCTAssertEqual(text, "fn main() {}")
    }

    func testNonStreamingChunkIsAlsoRead() async throws {
        let transport = FakeStreamTransport()
        transport.payloads = [#"{"choices":[{"message":{"content":"inteiro"}}]}"#]
        let client = AIClient(configuration: AIConfiguration(), apiKey: "k", transport: transport)

        let text = try await collect(try await client.streamReply(history))
        XCTAssertEqual(text, "inteiro")
    }

    func testUsageOnlyChunkIsIgnored() async throws {
        let transport = FakeStreamTransport()
        transport.payloads = [delta("a"), #"{"choices":[],"usage":{"total_tokens":3}}"#, delta("b")]
        let client = AIClient(configuration: AIConfiguration(), apiKey: "k", transport: transport)

        let text = try await collect(try await client.streamReply(history))
        XCTAssertEqual(text, "ab")
    }

    func testMissingKeyFailsBeforeTheRequest() async throws {
        let transport = FakeStreamTransport()
        let client = AIClient(configuration: AIConfiguration(), apiKey: "  ", transport: transport)

        do {
            _ = try await client.streamReply(history)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? AIError, .missingKey)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testInvalidBaseURLIsReported() async throws {
        let transport = FakeStreamTransport()
        var configuration = AIConfiguration()
        configuration.baseURL = "não é url"
        let client = AIClient(configuration: configuration, apiKey: "k", transport: transport)

        do {
            _ = try await client.streamReply(history)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? AIError, .invalidURL)
        }
    }

    func testErrorInsideTheStreamIsSurfaced() async throws {
        let transport = FakeStreamTransport()
        transport.payloads = [#"{"error":{"message":"modelo não existe"}}"#]
        let client = AIClient(configuration: AIConfiguration(), apiKey: "k", transport: transport)

        do {
            _ = try await collect(try await client.streamReply(history))
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? AIError, .http(status: 0, message: "modelo não existe"))
        }
    }

    func testUnauthorizedBodyMessageIsKept() {
        let error = AIError.from(status: 401, body: #"{"error":{"message":"Invalid API key"}}"#)
        XCTAssertEqual(error, .unauthorized("Invalid API key"))
    }

    func testRateLimitIsItsOwnError() {
        let error = AIError.from(status: 429, body: #"{"error":{"message":"slow down"}}"#)
        XCTAssertEqual(error, .rateLimited("slow down"))
    }

    func testProviderSwitchMovesDefaults() {
        var configuration = AIConfiguration()
        configuration.select(.gitHubModels)

        XCTAssertEqual(configuration.model, "openai/gpt-4o")
        XCTAssertEqual(configuration.baseURL, "https://models.github.ai/inference")

        configuration.baseURL = "http://meu-proxy/v1"
        configuration.select(.custom)
        XCTAssertEqual(configuration.baseURL, "http://meu-proxy/v1", "a URL própria sobrevive à troca")
    }

    func testConfigurationRoundTripsThroughJSON() throws {
        var original = AIConfiguration(provider: .custom, model: "llama3")
        original.temperature = 0.7
        original.applyEditsLive = false

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIConfiguration.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testDefaultPromptDescribesTheSupportedSubset() {
        let prompt = AIConfiguration.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("```goose"))
        XCTAssertTrue(prompt.contains("recursive fn"))
        XCTAssertTrue(prompt.contains("guard"))
        XCTAssertTrue(prompt.contains("Não use"))
    }
}

final class AIEditExtractorTests: XCTestCase {
    func testClosedBlockIsExtracted() {
        let reply = """
        Aqui está:

        ```goose
        fn main() {
            print("oi");
        }
        ```

        Pronto.
        """

        let block = AIEditExtractor.gooseBlock(in: reply)
        XCTAssertEqual(block?.closed, true)
        XCTAssertEqual(block?.code, "fn main() {\n    print(\"oi\");\n}\n")
    }

    func testOpenBlockStillYieldsTheCodeSoFar() {
        let reply = "```goose\nfn main() {\n    pri"

        let block = AIEditExtractor.gooseBlock(in: reply)
        XCTAssertEqual(block?.closed, false)
        XCTAssertEqual(block?.code, "fn main() {\n    pri")
    }

    func testNoBlockYieldsNil() {
        XCTAssertNil(AIEditExtractor.gooseBlock(in: "só texto, sem código"))
    }

    func testProseDropsTheBlock() {
        let reply = """
        Vou somar os números.

        ```goose
        fn main() { print(1 + 1); }
        ```
        """

        XCTAssertEqual(AIEditExtractor.prose(in: reply), "Vou somar os números.")
    }

    func testProseStopsAtAnUnclosedBlock() {
        let reply = "Explicando\n\n```goose\nfn main()"
        XCTAssertEqual(AIEditExtractor.prose(in: reply), "Explicando")
    }

    func testTwoBlocksKeepTheFirst() {
        let reply = """
        ```goose
        primeiro
        ```
        ```goose
        segundo
        ```
        """

        XCTAssertEqual(AIEditExtractor.gooseBlock(in: reply)?.code, "primeiro\n")
    }
}
