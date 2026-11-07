import SwiftUI

/// Commits the editor's text to the file it was opened from, or to a new file
/// in that repository.
struct GitHubCommitView: View {
    @ObservedObject var session: GitHubSession
    let source: String
    @Binding var openFile: GitHubSession.OpenFile?

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var path = ""
    @State private var branch = ""
    @State private var isCommitting = false
    @State private var errorMessage: String?
    @State private var result: String?

    private var canCommit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isCommitting
    }

    var body: some View {
        NavigationStack {
            Form {
                if let openFile {
                    Section {
                        LabeledContent("Repositório", value: openFile.repository)
                        LabeledContent("Branch", value: branch)
                        TextField("Caminho do arquivo", text: $path)
                            .font(.system(.footnote, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Destino")
                    } footer: {
                        Text("O commit substitui o arquivo na branch escolhida. Se ele mudou no GitHub depois que você abriu, o GitHub recusa e você recarrega antes.")
                    }
                } else {
                    Section {
                        Text("Abra um arquivo pelo menu GitHub → Abrir do GitHub antes de commitar.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if openFile != nil {
                    Section {
                        TextField("Mensagem do commit", text: $message, axis: .vertical)
                            .lineLimit(2...5)
                    } header: {
                        Text("Commit")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let result {
                    Section {
                        Label(result, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Commitar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await commit() }
                    } label: {
                        if isCommitting {
                            ProgressView()
                        } else {
                            Text("Commitar")
                        }
                    }
                    .disabled(!canCommit || openFile == nil)
                }
            }
            .onAppear(perform: prepare)
        }
    }

    private func prepare() {
        guard let openFile else { return }
        branch = openFile.branch
        path = openFile.path
    }

    private func commit() async {
        guard let openFile else { return }
        isCommitting = true
        errorMessage = nil
        result = nil
        defer { isCommitting = false }

        do {
            let commit = try await session.client.commit(
                source,
                to: path,
                in: openFile.repository,
                branch: branch,
                message: message,
                replacing: path == openFile.path ? openFile.sha : nil
            )
            // The blob changed, so the next commit has to quote the new one.
            // The commit response already carries it, so no extra request.
            let updated = GitHubSession.OpenFile(
                repository: openFile.repository,
                branch: branch,
                path: path,
                sha: commit.blobSHA ?? openFile.sha
            )
            openFile = updated
            session.remember(updated)
            result = "Commit \(commit.sha.prefix(7)) enviado."
            message = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
