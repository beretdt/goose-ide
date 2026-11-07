import Foundation
import SwiftUI

/// Holds the GitHub session for the whole app: the token, the account it
/// belongs to, and the file currently open from a repository.
///
/// The class is not actor-isolated on purpose: `@StateObject` builds it in a
/// non-isolated property initializer, and every mutation here happens from a
/// SwiftUI task, which already runs on the main actor.
final class GitHubSession: ObservableObject {
    @Published private(set) var token: String
    @Published private(set) var login: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    /// Where the open file came from, so a commit knows what to replace.
    private(set) var openFile: OpenFile?

    struct OpenFile: Equatable {
        let repository: String
        let branch: String
        let path: String
        let sha: String
    }

    init(token: String? = GitHubTokenStore.load()) {
        self.token = token ?? ""
    }

    var isConfigured: Bool {
        !token.isEmpty
    }

    var client: GitHubClient {
        GitHubClient(token: token)
    }

    /// Checks the token against the API, which catches a wrong scope early.
    func connect(with token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Cole um token do GitHub."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let user = try await GitHubClient(token: trimmed).viewer()
            self.token = trimmed
            login = user.login
            GitHubTokenStore.save(trimmed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        token = ""
        login = nil
        openFile = nil
        GitHubTokenStore.delete()
    }

    func remember(_ file: OpenFile) {
        openFile = file
    }

    func forgetOpenFile() {
        openFile = nil
    }
}
