import Foundation

/// One streaming POST. The transport yields the payload of each
/// `data:` line of the server-sent stream, already unwrapped, so the client
/// only has to read `choices[0].delta.content` out of it.
public struct AIStreamRequest: Equatable {
    public var url: URL
    public var headers: [String: String]
    public var body: Data

    public init(url: URL, headers: [String: String], body: Data) {
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public protocol AIStreamingTransport: Sendable {
    func stream(_ request: AIStreamRequest) async throws -> AsyncThrowingStream<String, Error>
}

/// The real transport: `URLSession` bytes, split into server-sent events.
public struct URLSessionAIStreamTransport: AIStreamingTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func stream(_ request: AIStreamRequest) async throws -> AsyncThrowingStream<String, Error> {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = 120
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        #if canImport(FoundationNetworking)
        // swift-corelibs-foundation has no `bytes(for:)`, so the whole body is
        // read and split here. The stream is still emitted chunk by chunk;
        // only the arrival is batched.
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.emptyReply
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.from(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let payloads = Self.payloads(in: String(decoding: data, as: UTF8.self))
        return AsyncThrowingStream { continuation in
            for payload in payloads {
                continuation.yield(payload)
            }
            continuation.finish()
        }
        #else
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.emptyReply
        }
        guard (200..<300).contains(http.statusCode) else {
            var collected = Data()
            for try await byte in bytes {
                collected.append(byte)
                if collected.count > 8_192 { break }
            }
            throw AIError.from(status: http.statusCode, body: String(decoding: collected, as: UTF8.self))
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        if let payload = Self.payload(in: line) {
                            continuation.yield(payload)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        #endif
    }

    /// One `data:` line as a payload, or nil for comments and blanks.
    private static func payload(in line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload.isEmpty || payload == "[DONE]" { return nil }
        return payload
    }

    private static func payloads(in body: String) -> [String] {
        body.split(whereSeparator: \.isNewline)
            .compactMap { payload(in: String($0)) }
    }
}

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
