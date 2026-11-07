import SwiftUI
import GooseAI

/// Provider, key, model, prompt and sampling, tuned to be usable with thumbs.
struct AISettingsView: View {
    @ObservedObject var chat: ChatSession

    @Environment(\.dismiss) private var dismiss
    @State private var configuration = AIConfiguration()
    @State private var key = ""
    @State private var keyVisible = false
    @State private var promptExpanded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Provedor") {
                    Picker("Provedor", selection: Binding(
                        get: { configuration.provider },
                        set: { provider in
                            configuration.select(provider)
                            key = AIKeyStore.load(for: provider) ?? ""
                        }
                    )) {
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    if configuration.provider == .gitHubModels {
                        Text(AIProvider.gitHubModels.keyHint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Group {
                            if keyVisible {
                                TextField("Chave da API", text: $key)
                            } else {
                                SecureField("Chave da API", text: $key)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))

                        Button {
                            keyVisible.toggle()
                        } label: {
                            Image(systemName: keyVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(keyVisible ? "Ocultar chave" : "Mostrar chave")
                    }
                } header: {
                    Text("Chave")
                } footer: {
                    Text("\(configuration.provider.keyHint) A chave fica no Keychain deste iPhone.")
                }

                Section("Modelo") {
                    TextField("Modelo", text: $configuration.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))

                    if configuration.provider == .custom || configuration.provider == .openRouter {
                        TextField("URL base", text: $configuration.baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Aplicar no editor ao vivo", isOn: $configuration.applyEditsLive)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Temperatura")
                            Spacer()
                            Text(String(format: "%.1f", configuration.temperature))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $configuration.temperature, in: 0...1, step: 0.1)
                    }

                    Stepper(
                        "Máximo de tokens: \(configuration.maxTokens)",
                        value: $configuration.maxTokens,
                        in: 256...8_192,
                        step: 256
                    )
                } header: {
                    Text("Comportamento")
                } footer: {
                    Text("Com \"ao vivo\" ligado, o código que o agente escreve aparece no editor enquanto ele responde; você pode desfazer.")
                }

                Section {
                    DisclosureGroup("Instruções do agente", isExpanded: $promptExpanded) {
                        TextEditor(text: $configuration.systemPrompt)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 160)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled()

                        Button("Restaurar as instruções padrão") {
                            configuration.systemPrompt = AIConfiguration.defaultSystemPrompt
                        }
                        .font(.footnote)
                    }
                } footer: {
                    Text("As instruções dizem ao modelo o subconjunto de Goose que o app executa, para ele não escrever código que não roda aqui.")
                }
            }
            .navigationTitle("Agente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        chat.update(configuration)
                        chat.saveKey(key)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                configuration = chat.configuration
                key = AIKeyStore.load(for: configuration.provider) ?? ""
            }
        }
    }
}
