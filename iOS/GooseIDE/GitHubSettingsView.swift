import SwiftUI

/// Token setup and account state.
struct GitHubSettingsView: View {
    @ObservedObject var session: GitHubSession
    @Environment(\.dismiss) private var dismiss
    @State private var draftToken = ""
    @State private var isVisible = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if session.isConfigured {
                        LabeledContent("Conta", value: session.login ?? "conectada")
                        Button("Desconectar", role: .destructive) {
                            session.disconnect()
                            draftToken = ""
                        }
                    } else {
                        HStack {
                            Group {
                                if isVisible {
                                    TextField("ghp_…", text: $draftToken)
                                } else {
                                    SecureField("ghp_…", text: $draftToken)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.footnote, design: .monospaced))

                            Button {
                                isVisible.toggle()
                            } label: {
                                Image(systemName: isVisible ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(isVisible ? "Ocultar token" : "Mostrar token")
                        }

                        Button {
                            Task { await session.connect(with: draftToken) }
                        } label: {
                            if session.isLoading {
                                ProgressView()
                            } else {
                                Text("Conectar")
                            }
                        }
                        .disabled(draftToken.isEmpty || session.isLoading)
                    }
                } header: {
                    Text("Token do GitHub")
                } footer: {
                    Text("""
                    Crie em GitHub → Settings → Developer settings → Personal access tokens. \
                    Um token fine-grained precisa de Contents: read and write no repositório; \
                    um clássico precisa do escopo repo.

                    O token fica no Keychain deste iPhone e só é enviado para api.github.com.
                    """)
                }

                if let errorMessage = session.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pronto") { dismiss() }
                }
            }
        }
    }
}
