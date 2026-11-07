import Foundation

// MARK: - Transport

/// One HTTP call, in the shape the GitHub client needs. Keeping it a plain
/// value (instead of `URLRequest`) lets the tests drive the client without a
/// network and keeps the client free of platform-only APIs.
public struct HTTPRequest: Equatable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Equatable {
    public var status: Int
    public var body: Data
    public var headers: [String: String]

    public init(status: Int, body: Data, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// The real transport. `FoundationNetworking` is where `URLSession` lives on
/// Linux, so the import is conditional.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.unexpectedResponse
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let name = key as? String, let text = value as? String {
                headers[name.lowercased()] = text
            }
        }
        return HTTPResponse(status: http.statusCode, body: data, headers: headers)
    }
}

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
