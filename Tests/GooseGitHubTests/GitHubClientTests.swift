import XCTest
@testable import GooseGitHub

/// Drives the client without a network: each call is recorded and answered
/// with a canned response.
private final class FakeTransport: HTTPTransport, @unchecked Sendable {
    var responses: [HTTPResponse] = []
    private(set) var requests: [HTTPRequest] = []

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw GitHubError.unexpectedResponse
        }
        return responses.removeFirst()
    }
}

private func response(_ json: String, status: Int = 200, headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(status: status, body: Data(json.utf8), headers: headers)
}

final class GitHubClientTests: XCTestCase {
    func testViewerSendsTokenAndDecodesLogin() async throws {
        let transport = FakeTransport()
        transport.responses = [response(#"{"login": "beretdt", "name": "Davi Lins"}"#)]
        let client = GitHubClient(token: "t0ken", transport: transport)

        let user = try await client.viewer()

        XCTAssertEqual(user.login, "beretdt")
        XCTAssertEqual(transport.requests.count, 1)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.absoluteString, "https://api.github.com/user")
        XCTAssertEqual(request.headers["Authorization"], "Bearer t0ken")
        XCTAssertEqual(request.headers["Accept"], "application/vnd.github+json")
    }

    func testMissingTokenFailsBeforeAnyRequest() async throws {
        let transport = FakeTransport()
        let client = GitHubClient(token: "", transport: transport)

        do {
            _ = try await client.viewer()
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? GitHubError, .missingToken)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testRepositoriesDecodeOwnerAndDefaults() async throws {
        let transport = FakeTransport()
        transport.responses = [response("""
        [
          {"full_name": "beretdt/goose-ide", "name": "goose-ide", "owner": {"login": "beretdt"},
           "private": true, "default_branch": "main", "description": "Goose no iPhone"},
          {"full_name": "beretdt/outro", "name": "outro", "owner": {"login": "beretdt"},
           "private": false, "default_branch": "trunk"}
        ]
        """)]
        let client = GitHubClient(token: "t", transport: transport)

        let repositories = try await client.repositories()

        XCTAssertEqual(repositories.count, 2)
        XCTAssertEqual(repositories[0].fullName, "beretdt/goose-ide")
        XCTAssertEqual(repositories[0].owner, "beretdt")
        XCTAssertTrue(repositories[0].isPrivate)
        XCTAssertEqual(repositories[0].defaultBranch, "main")
        XCTAssertEqual(repositories[1].description, nil)
        XCTAssertEqual(repositories[1].id, "beretdt/outro")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.query, "per_page=100&sort=pushed")
    }

    func testBranchSHAComesFromNestedCommit() async throws {
        let transport = FakeTransport()
        transport.responses = [response("""
        [{"name": "main", "commit": {"sha": "abc123"}}, {"name": "dev", "commit": {"sha": "def456"}}]
        """)]
        let client = GitHubClient(token: "t", transport: transport)

        let branches = try await client.branches(of: "beretdt/goose-ide")

        XCTAssertEqual(branches.map(\.name), ["main", "dev"])
        XCTAssertEqual(branches[0].commitSHA, "abc123")
    }

    func testGooseFilesFiltersAndSortsTheTree() async throws {
        let transport = FakeTransport()
        transport.responses = [response("""
        {"tree": [
          {"path": "Sources", "sha": "1", "type": "tree"},
          {"path": "Tests/Fixtures/b.goose", "sha": "2", "type": "blob"},
          {"path": "README.md", "sha": "3", "type": "blob"},
          {"path": "Tests/Fixtures/a.goose", "sha": "4", "type": "blob"}
        ]}
        """)]
        let client = GitHubClient(token: "t", transport: transport)

        let files = try await client.gooseFiles(in: "beretdt/goose-ide", ref: "main")

        XCTAssertEqual(files.map(\.path), ["Tests/Fixtures/a.goose", "Tests/Fixtures/b.goose"])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.path, "/repos/beretdt/goose-ide/git/trees/main")
        XCTAssertEqual(request.url.query, "recursive=1")
    }

    func testReadFileDecodesBase64AndKeepsItsBlobId() async throws {
        let text = "fn main() {\n    print(\"olá\");\n}\n"
        let encoded = Data(text.utf8).base64EncodedString()
        // GitHub wraps the base64 payload across lines.
        let wrapped = encoded.enumerated().map { index, character in
            index > 0 && index % 60 == 0 ? "\n\(character)" : String(character)
        }.joined()

        let transport = FakeTransport()
        transport.responses = [response("""
        {"path": "samples/ola.goose", "sha": "blob7", "encoding": "base64", "content": "\(wrapped)"}
        """)]
        let client = GitHubClient(token: "t", transport: transport)

        let file = try await client.readFile("samples/ola.goose", in: "beretdt/goose-ide", ref: "main")

        XCTAssertEqual(file.text, text)
        XCTAssertEqual(file.sha, "blob7")
        XCTAssertEqual(file.path, "samples/ola.goose")
    }

    func testReadFileEncodesSpacesInThePath() async throws {
        let transport = FakeTransport()
        transport.responses = [response(#"{"path": "a b/goose file.goose", "sha": "s", "encoding": "base64", "content": "eA=="}"#)]
        let client = GitHubClient(token: "t", transport: transport)

        _ = try await client.readFile("a b/goose file.goose", in: "o/r", ref: "main")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.path, "/repos/o/r/contents/a%20b/goose%20file.goose")
        XCTAssertEqual(request.url.query, "ref=main")
    }

    func testCommitSendsMessageContentAndBranch() async throws {
        let transport = FakeTransport()
        transport.responses = [response(
            #"{"content": {"sha": "newblob"}, "commit": {"sha": "newsha", "message": "olá"}}"#,
            status: 201
        )]
        let client = GitHubClient(token: "t", transport: transport)

        let commit = try await client.commit(
            "print(1);",
            to: "samples/ola.goose",
            in: "beretdt/goose-ide",
            branch: "main",
            message: "olá",
            replacing: nil
        )

        XCTAssertEqual(commit.sha, "newsha")
        XCTAssertEqual(commit.blobSHA, "newblob")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "PUT")

        let body = try XCTUnwrap(request.body)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["message"] as? String, "olá")
        XCTAssertEqual(payload["branch"] as? String, "main")
        XCTAssertNil(payload["sha"])
        XCTAssertEqual(
            payload["content"] as? String,
            Data("print(1);".utf8).base64EncodedString()
        )
    }

    func testCommitQuotesTheBlobIdWhenReplacing() async throws {
        let transport = FakeTransport()
        transport.responses = [response(#"{"commit": {"sha": "s2", "message": "m"}}"#)]
        let client = GitHubClient(token: "t", transport: transport)

        _ = try await client.commit(
            "x", to: "a.goose", in: "o/r", branch: "dev", message: "m", replacing: "blob7"
        )

        let body = try XCTUnwrap(transport.requests.first?.body)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["sha"] as? String, "blob7")
        XCTAssertEqual(payload["branch"] as? String, "dev")
    }

    // MARK: - Errors

    func testUnauthorizedIsReadable() async throws {
        let transport = FakeTransport()
        transport.responses = [response("{}", status: 401)]
        let client = GitHubClient(token: "bad", transport: transport)

        do {
            _ = try await client.viewer()
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? GitHubError, .unauthorized)
            XCTAssertTrue(error.localizedDescription.contains("Token inválido"))
        }
    }

    func testNotFoundNamesTheRequestedPath() async throws {
        let transport = FakeTransport()
        transport.responses = [response("{}", status: 404)]
        let client = GitHubClient(token: "t", transport: transport)

        do {
            _ = try await client.readFile("sumiu.goose", in: "o/r", ref: "main")
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? GitHubError, .notFound(what: "/repos/o/r/contents/sumiu.goose"))
        }
    }

    func testRateLimitReportsTheResetTime() async throws {
        let transport = FakeTransport()
        transport.responses = [
            response("{}", status: 403, headers: [
                "x-ratelimit-remaining": "0",
                "x-ratelimit-reset": "1800000000",
            ])
        ]
        let client = GitHubClient(token: "t", transport: transport)

        do {
            _ = try await client.viewer()
            XCTFail("expected a failure")
        } catch {
            guard case let .rateLimited(reset)? = error as? GitHubError else {
                return XCTFail("expected a rate limit error, got \(error)")
            }
            XCTAssertEqual(reset, Date(timeIntervalSince1970: 1_800_000_000))
        }
    }

    func testConflictIsReportedWhenTheFileChanged() async throws {
        let transport = FakeTransport()
        transport.responses = [response("{}", status: 409)]
        let client = GitHubClient(token: "t", transport: transport)

        do {
            _ = try await client.commit("x", to: "a.goose", in: "o/r", branch: "m", message: "m", replacing: "old")
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? GitHubError, .conflict)
            XCTAssertTrue(error.localizedDescription.contains("mudou no GitHub"))
        }
    }

    func testForbiddenWithoutRateHeadersIsAPermissionProblem() async throws {
        let transport = FakeTransport()
        transport.responses = [response("{}", status: 403)]
        let client = GitHubClient(token: "t", transport: transport)

        do {
            _ = try await client.viewer()
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? GitHubError, .forbidden(reason: nil))
        }
    }

    func testBrokenJSONIsADecodingError() async throws {
        let transport = FakeTransport()
        transport.responses = [response("not json")]
        let client = GitHubClient(token: "t", transport: transport)

        do {
            _ = try await client.viewer()
            XCTFail("expected a failure")
        } catch {
            guard case .decoding = error as? GitHubError else {
                return XCTFail("expected a decoding error, got \(error)")
            }
        }
    }
}
