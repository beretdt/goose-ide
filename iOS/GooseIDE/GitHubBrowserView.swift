import SwiftUI

/// Picks a repository, a branch and a `.goose` file, then hands the text back
/// to the editor.
struct GitHubBrowserView: View {
    @ObservedObject var session: GitHubSession
    @Binding var source: String
    @Binding var openFile: GitHubSession.OpenFile?
    let onWillOpen: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var repositories: [GitHubRepository] = []
    @State private var search = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filtered: [GitHubRepository] {
        guard !search.isEmpty else { return repositories }
        return repositories.filter { $0.fullName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    ForEach(filtered) { repository in
                        NavigationLink {
                            GitHubFileListView(
                                session: session,
                                repository: repository,
                                source: $source,
                                openFile: $openFile,
                                onWillOpen: onWillOpen,
                                onOpen: { dismiss() }
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(repository.fullName)
                                        .font(.subheadline.weight(.medium))
                                    if repository.isPrivate {
                                        Image(systemName: "lock.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if let description = repository.description, !description.isEmpty {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                } footer: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("\(repositories.count) repositório(s)")
                    }
                }
            }
            .searchable(text: $search, prompt: "Filtrar repositórios")
            .navigationTitle("Abrir do GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Recarregar")
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            repositories = try await session.client.repositories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Branches and `.goose` files of one repository.
private struct GitHubFileListView: View {
    @ObservedObject var session: GitHubSession
    let repository: GitHubRepository
    @Binding var source: String
    @Binding var openFile: GitHubSession.OpenFile?
    let onWillOpen: () -> Void
    let onOpen: () -> Void

    @State private var branches: [String] = []
    @State private var branch = ""
    @State private var files: [GitHubEntry] = []
    @State private var isLoading = false
    @State private var openingPath: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Picker("Branch", selection: $branch) {
                    ForEach(branches, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .onChange(of: branch) { newValue in
                    guard !newValue.isEmpty else { return }
                    Task { await loadFiles(ref: newValue) }
                }
            }

            Section {
                if isLoading {
                    ProgressView()
                } else if files.isEmpty {
                    Text("Nenhum arquivo .goose nesta branch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(files) { file in
                        Button {
                            Task { await open(file) }
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                Text(file.path)
                                    .font(.system(.footnote, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                if openingPath == file.path {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(openingPath != nil)
                    }
                }
            } header: {
                Text("Arquivos")
            } footer: {
                if let openFile, openFile.repository == repository.fullName {
                    Text("Aberto: \(openFile.path) (\(openFile.branch))")
                        .font(.caption2)
                }
            }
        }
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadBranches() }
    }

    private func loadBranches() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let names = try await session.client.branches(of: repository.fullName).map(\.name)
            branches = names
            branch = names.contains(repository.defaultBranch)
                ? repository.defaultBranch
                : (names.first ?? "")
            if !branch.isEmpty {
                await loadFiles(ref: branch)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadFiles(ref: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            files = try await session.client.gooseFiles(in: repository.fullName, ref: ref)
        } catch {
            files = []
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ entry: GitHubEntry) async {
        openingPath = entry.path
        errorMessage = nil
        defer { openingPath = nil }

        do {
            let file = try await session.client.readFile(
                entry.path,
                in: repository.fullName,
                ref: branch
            )
            onWillOpen()
            source = file.text
            let opened = GitHubSession.OpenFile(
                repository: repository.fullName,
                branch: branch,
                path: file.path,
                sha: file.sha
            )
            openFile = opened
            session.remember(opened)
            onOpen()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
