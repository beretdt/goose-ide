import Foundation

public struct GitHubUser: Decodable, Equatable {
    public let login: String
    public let name: String?
}

public struct GitHubRepository: Decodable, Equatable, Identifiable {
    public let fullName: String
    public let name: String
    public let owner: String
    public let isPrivate: Bool
    public let defaultBranch: String
    public let description: String?

    public var id: String { fullName }

    private enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case name
        case owner
        case isPrivate = "private"
        case defaultBranch = "default_branch"
        case description
    }

    private struct Owner: Decodable {
        let login: String
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fullName = try container.decode(String.self, forKey: .fullName)
        name = try container.decode(String.self, forKey: .name)
        owner = try container.decode(Owner.self, forKey: .owner).login
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        defaultBranch = try container.decodeIfPresent(String.self, forKey: .defaultBranch) ?? "main"
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }
}

public struct GitHubBranch: Decodable, Equatable, Identifiable {
    public let name: String
    public let commitSHA: String

    public var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name
        case commit
    }

    private struct Commit: Decodable {
        let sha: String
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        commitSHA = try container.decode(Commit.self, forKey: .commit).sha
    }
}

public struct GitHubEntry: Decodable, Equatable, Identifiable {
    public enum Kind: String, Decodable {
        case blob
        case tree
    }

    public let path: String
    public let sha: String
    public let kind: Kind

    public var id: String { path }

    private enum CodingKeys: String, CodingKey {
        case path
        case sha
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        sha = try container.decode(String.self, forKey: .sha)
        kind = try container.decodeIfPresent(Kind.self, forKey: .type) ?? .blob
    }
}

/// A file's text plus the blob id a commit has to quote when replacing it.
public struct GitHubFile: Equatable {
    public let path: String
    public let sha: String
    public let text: String
}

/// What a commit answers with, enough for the app to keep working: the commit
/// id, and the blob id of the file as it now stands.
public struct GitHubCommit: Equatable {
    public let sha: String
    public let message: String
    public let blobSHA: String?
}
