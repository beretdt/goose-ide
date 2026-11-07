import Foundation

/// Reads and writes a repository through the GitHub REST API.
///
/// The token is a fine-grained or classic personal access token with the
/// `repo` (or `Contents: read and write`) scope. Nothing else is needed: the
/// app talks to `api.github.com` directly, so no clone and no git on the
/// device.
public struct GitHubClient {
    private static let api = URL(string: "https://api.github.com")!

    private let token: String
    private let transport: HTTPTransport

    public init(token: String, transport: HTTPTransport = URLSessionTransport()) {
        self.token = token
        self.transport = transport
    }

    // MARK: - Account

    public func viewer() async throws -> GitHubUser {
        try decode(GitHubUser.self, from: try await get("/user"), what: "usuário")
    }

    // MARK: - Repositories

    /// Repositories the token can see, most recently pushed first.
    public func repositories() async throws -> [GitHubRepository] {
        let data = try await get("/user/repos", query: [
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "sort", value: "pushed"),
        ])
        return try decode([GitHubRepository].self, from: data, what: "repositórios")
    }

    public func branches(of repository: String) async throws -> [GitHubBranch] {
        let data = try await get("/repos/\(repository)/branches", query: [
            URLQueryItem(name: "per_page", value: "100"),
        ])
        return try decode([GitHubBranch].self, from: data, what: "branches de \(repository)")
    }

    /// Every file of a branch, flattened. The tree call returns directories
    /// too; they are dropped here so callers only see what can be opened.
    public func files(in repository: String, ref: String) async throws -> [GitHubEntry] {
        let data = try await get("/repos/\(repository)/git/trees/\(ref)", query: [
            URLQueryItem(name: "recursive", value: "1"),
        ])
        let tree = try decode(TreeResponse.self, from: data, what: "arquivos de \(repository)")
        return tree.tree.filter { $0.kind == .blob }
    }

    /// The `.goose` files of a branch, which is what the editor can open.
    public func gooseFiles(in repository: String, ref: String) async throws -> [GitHubEntry] {
        try await files(in: repository, ref: ref)
            .filter { $0.path.hasSuffix(".goose") }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: - Files

    public func readFile(_ path: String, in repository: String, ref: String) async throws -> GitHubFile {
        let data = try await get("/repos/\(repository)/contents/\(encodePath(path))", query: [
            URLQueryItem(name: "ref", value: ref),
        ])
        let contents = try decode(ContentsResponse.self, from: data, what: path)

        guard contents.encoding == "base64", let encoded = contents.content else {
            throw GitHubError.unexpectedResponse
        }
        let cleaned = encoded.replacingOccurrences(of: "\n", with: "")
        guard let bytes = Data(base64Encoded: cleaned) else {
            throw GitHubError.decoding("conteúdo do arquivo não é base64 válido")
        }
        return GitHubFile(
            path: contents.path,
            sha: contents.sha,
            text: String(decoding: bytes, as: UTF8.self)
        )
    }

    /// Creates or replaces a file. Pass the blob id the file had when it was
    /// read; GitHub rejects the commit if someone else changed it since, which
    /// is what keeps a stale editor from overwriting newer work.
    public func commit(
        _ text: String,
        to path: String,
        in repository: String,
        branch: String,
        message: String,
        replacing sha: String?
    ) async throws -> GitHubCommit {
        var payload: [String: Any] = [
            "message": message,
            "content": Data(text.utf8).base64EncodedString(),
            "branch": branch,
        ]
        if let sha {
            payload["sha"] = sha
        }

        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await send(
            method: "PUT",
            path: "/repos/\(repository)/contents/\(encodePath(path))",
            body: body
        )
        return try decode(PutResponse.self, from: data, what: "commit").commit
    }

    // MARK: - Requests

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        try await send(method: "GET", path: path, query: query, body: nil)
    }

    private func send(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data?
    ) async throws -> Data {
        guard !token.isEmpty else { throw GitHubError.missingToken }

        var components = URLComponents(
            url: Self.api.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else {
            throw GitHubError.unexpectedResponse
        }

        let request = HTTPRequest(
            method: method,
            url: url,
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "GooseIDE",
                "Content-Type": "application/json",
            ],
            body: body
        )

        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else {
            throw GitHubError.from(status: response.status, headers: response.headers, what: path)
        }
        return response.body
    }

    /// Percent-encodes each path segment but keeps the slashes, so a file
    /// called `meu programa.goose` still resolves.
    private func encodePath(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? String(segment)
            }
            .joined(separator: "/")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, what: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GitHubError.decoding("\(what): \(error.localizedDescription)")
        }
    }

    // MARK: - Wiring shapes

    private struct TreeResponse: Decodable {
        let tree: [GitHubEntry]
    }

    private struct ContentsResponse: Decodable {
        let path: String
        let sha: String
        let content: String?
        let encoding: String?
    }

    private struct PutResponse: Decodable {
        let commit: GitHubCommit

        private enum CodingKeys: String, CodingKey {
            case commit
            case content
        }

        private struct Commit: Decodable {
            let sha: String
            let message: String
        }

        private struct Content: Decodable {
            let sha: String
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let nested = try container.decode(Commit.self, forKey: .commit)
            let blob = try container.decodeIfPresent(Content.self, forKey: .content)
            commit = GitHubCommit(sha: nested.sha, message: nested.message, blobSHA: blob?.sha)
        }
    }
}
