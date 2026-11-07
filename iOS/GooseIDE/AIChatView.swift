import SwiftUI
import GooseAI

/// The AI chat, presented as a half sheet so the code stays visible while the
/// agent edits it.
struct AIChatView: View {
    @ObservedObject var chat: ChatSession
    let program: String
    let onUndo: () -> Void
    var canUndo: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showingSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            bar
            transcript
            composer
        }
        .background(VSCode.sidebar)
        .sheet(isPresented: $showingSettings) {
            AISettingsView(session: chat)
        }
        .onAppear {
            if !chat.hasKey {
                // First run: send the person straight to the key screen.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showingSettings = true
                }
            }
        }
    }

    // MARK: - Bar

    private var bar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .foregroundStyle(VSCode.keyword)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 1) {
                Text("Agente")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VSCode.text)
                Text(chat.configuration.model)
                    .font(.caption2)
                    .foregroundStyle(VSCode.faintText)
                    .lineLimit(1)
            }

            Spacer()

            if chat.isStreaming {
                Button {
                    chat.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(VSCode.error)
                }
                .accessibilityLabel("Parar a resposta")
            }

            Button {
                chat.clearConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline)
            }
            .foregroundStyle(VSCode.dimText)
            .disabled(chat.messages.isEmpty)
            .accessibilityLabel("Nova conversa")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.subheadline)
            }
            .foregroundStyle(VSCode.dimText)
            .accessibilityLabel("Configurações do agente")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(VSCode.titleBar)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if chat.messages.isEmpty {
                        emptyState
                    }

                    ForEach(chat.messages) { message in
                        bubble(for: message)
                            .id(message.id)
                    }

                    if let errorMessage = chat.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(VSCode.error)
                            .padding(.horizontal, 12)
                    }

                    if chat.liveEdit != nil {
                        liveEditRow
                    }
                }
                .padding(12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.last?.content) { _ in
                guard let lastId = chat.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Peça uma mudança no código.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(VSCode.text)

            ForEach(Self.suggestions, id: \.self) { suggestion in
                Button {
                    draft = suggestion
                } label: {
                    Text(suggestion)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(VSCode.titleBar)
                        .foregroundStyle(VSCode.dimText)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
    }

    private static let suggestions = [
        "Escreva um programa que calcule a sequência de Fibonacci até 15.",
        "Troque o laço por uma versão com match e me explique.",
        "Encontre um erro neste programa e corrija.",
    ]

    private func bubble(for message: AIChatMessage) -> some View {
        let isUser = message.role == .user

        return VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Text(isUser ? "você" : "agente")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(VSCode.faintText)

            Text(displayText(for: message) + (isStreaming(message) ? "▍" : ""))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(VSCode.text)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isUser ? VSCode.highlight : VSCode.titleBar)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    /// The bubble shows the prose only; the code lives in the editor.
    private func displayText(for message: AIChatMessage) -> String {
        guard message.role == .assistant else { return message.content }
        let prose = AIEditExtractor.prose(in: message.content)
        return prose.isEmpty ? "(editando o código…)" : prose
    }

    private func isStreaming(_ message: AIChatMessage) -> Bool {
        chat.isStreaming && message.id == chat.messages.last?.id
    }

    private var liveEditRow: some View {
        HStack(spacing: 8) {
            Image(systemName: chat.liveEditClosed ? "checkmark.circle.fill" : "ellipsis.circle.fill")
                .foregroundStyle(chat.liveEditClosed ? VSCode.success : VSCode.keyword)

            Text(chat.liveEditClosed ? "Código aplicado ao editor" : "Escrevendo no editor…")
                .font(.caption)
                .foregroundStyle(VSCode.dimText)

            Spacer()

            if canUndo {
                Button("Desfazer") { onUndo() }
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(VSCode.titleBar)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(VSCode.panelBorder)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Pedir ao agente…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.footnote)
                    .foregroundStyle(VSCode.text)
                    .textInputAutocapitalization(.sentences)
                    .focused($inputFocused)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(VSCode.editorBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityIdentifier("chatInput")

                Button {
                    send()
                } label: {
                    Image(systemName: chat.isStreaming ? "hourglass" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? VSCode.statusBar : VSCode.faintText)
                }
                .disabled(!canSend)
                .accessibilityLabel("Enviar")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(VSCode.titleBar)

            if !chat.hasKey {
                Button {
                    showingSettings = true
                } label: {
                    Text("Falta a chave da API — toque para configurar")
                        .font(.caption2)
                        .foregroundStyle(VSCode.warning)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .background(VSCode.titleBar)
            }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !chat.isStreaming
            && chat.hasKey
    }

    private func send() {
        let prompt = draft
        draft = ""
        inputFocused = false
        chat.send(prompt, program: program)
    }
}


