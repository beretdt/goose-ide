import SwiftUI
import UIKit
import GooseAI

// MARK: - Samples

struct GooseExample: Identifiable {
    let id = UUID()
    let name: String
    let source: String

    static let all: [GooseExample] = [
        GooseExample(
            name: "Olá, Goose",
            source: """
            fn main() {
                print("Olá, Goose!");
                print("A resposta é ", 42);
            }
            """
        ),
        GooseExample(
            name: "Fibonacci",
            source: """
            recursive fn fib(n: i64) -> i64 {
                if n < 2 { return n; }
                return fib(n - 1) + fib(n - 2);
            }

            fn main() {
                for i in 10 {
                    print("fib(", i, ") = ", fib(i));
                }
            }
            """
        ),
        GooseExample(
            name: "Arrays",
            source: """
            fn main() {
                var squares: i64[>..] = [];
                for i in 8 { squares.push(i * i); }
                print("quadrados: ", squares);
                print("quantidade: ", squares.len);

                var stack: i64[>..<] = [];
                stack.push(1); stack.push(2); stack.push(3);
                print("topo: ", stack.pop());
                print("pilha: ", stack);
            }
            """
        ),
        GooseExample(
            name: "Structs",
            source: """
            struct Point { x: f64, y: f64 }
            struct Player { name: u8[..16], pos: Point, hp: i32 = 100, alive: bool = true }

            fn main() {
                var p = Player { name: "gus", pos: Point { 1.0, 2.0 } };
                print(p);
                p.hp -= 30;
                p.pos = p.pos + Point { 0.5, 0.5 };
                print(p);
                print(p.name, " at ", p.pos.x, ",", p.pos.y, " hp ", p.hp);
            }
            """
        ),
        GooseExample(
            name: "Enums e match",
            source: """
            enum Shape { Circle { r: f64 }, Rect { w: f64, h: f64 }, Dot }

            fn area(s: Shape) -> f64 {
                match s {
                    Circle c => 3.14159 * c.r * c.r,
                    Rect r => r.w * r.h,
                    Dot => 0.0,
                }
            }

            fn main() {
                var shapes: Shape[>..] = [];
                shapes.push(Shape.Circle { r: 1.0 });
                shapes.push(Shape.Rect { w: 2.0, h: 3.0 });
                shapes.push(Shape.Dot);
                for s in shapes { print(s, " area ", area(s)); }

                let level = match 42 { 0 => "zero", 1..50 => "baixo", _ => "alto" };
                print("nível: ", level);
            }
            """
        ),
        GooseExample(
            name: "Slices",
            source: """
            fn total(xs: i64[:]) -> i64 {
                var t = 0;
                for x in xs { t += x; }
                return t;
            }

            fn main() {
                var grow: i64[>..] = [];
                for i in 5 { grow.push(i); }
                print("tudo: ", grow, " soma ", total(grow));
                print("1..4: ", grow[1..4], " soma ", total(grow[1..4]));
                print("últimos 2: ", grow[^2..]);

                for i in 10..13 { print("faixa ", i); }
            }
            """
        ),
        GooseExample(
            name: "Resultados e guard",
            source: """
            fn divide(a: i64, b: i64) -> i64, bool {
                if b == 0 { return 0, false; }
                return a / b, true;
            }

            fn show(n: i64) {
                guard n > 0;
                print("positivo: ", n);
            }

            fn main() {
                let q, ok = divide(7, 2);
                print(q, " ", ok);
                show(5);
                show(-1);

                defer print("fim");
                var xs: i64[>..] = [];
                for i in 4 { xs.push(i); }
                for &x in xs { x *= 2; }
                print(xs);
            }
            """
        ),
        GooseExample(
            name: "FizzBuzz",
            source: """
            fn main() {
                for i in 16 {
                    let word: u8[>..] = if i % 15 == 0 { "FizzBuzz" }
                        else if i % 3 == 0 { "Fizz" }
                        else if i % 5 == 0 { "Buzz" }
                        else { str(i) };
                    print(word);
                }
            }
            """
        ),
    ]
}

// MARK: - Draft

/// Keeps the last program on disk, so closing the app does not throw away
/// what was being written.
private enum GooseDraft {
    private static let key = "goose.draft.source"

    static func load() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func save(_ source: String) {
        UserDefaults.standard.set(source, forKey: key)
    }
}

// MARK: - Content

struct ContentView: View {
    @State private var source = GooseDraft.load() ?? GooseExample.all[0].source
    @State private var output = ""
    @State private var status: RunStatus = .idle
    @State private var isRunning = false
    @State private var elapsed: Double?
    @State private var saveTask: Task<Void, Never>?
    @State private var showOutput = true
    @State private var sourceBeforeAI: String?

    @StateObject private var github = GitHubSession()
    @StateObject private var chat = ChatSession()
    @State private var openFile: GitHubSession.OpenFile?
    @State private var showingBrowser = false
    @State private var showingCommit = false
    @State private var showingGitHubSettings = false
    @State private var showingChat = false

    private enum RunStatus {
        case idle
        case ok
        case failure

        var label: String {
            switch self {
            case .idle: return "pronto"
            case .ok: return "executado"
            case .failure: return "erro"
            }
        }

        var color: Color {
            switch self {
            case .idle: return VSCode.dimText
            case .ok: return VSCode.success
            case .failure: return VSCode.error
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            editor
            if showOutput {
                panel
            }
            statusBar
        }
        .background(VSCode.editorBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            activityBar
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingGitHubSettings) {
            GitHubSettingsView(session: github)
        }
        .sheet(isPresented: $showingBrowser) {
            GitHubBrowserView(session: github, source: $source, openFile: $openFile)
        }
        .sheet(isPresented: $showingCommit) {
            GitHubCommitView(session: github, source: source, openFile: $openFile)
        }
        .sheet(isPresented: $showingChat) {
            AIChatView(
                chat: chat,
                program: source,
                onUndo: undoAIEdit,
                canUndo: sourceBeforeAI != nil
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // One-parameter form: the two-parameter `onChange` is iOS 17 only.
        .onChange(of: source) { newValue in
            scheduleSave(newValue)
        }
        // The agent writes into the editor while it is still answering.
        .onChange(of: chat.liveEdit) { newValue in
            guard let code = newValue, chat.configuration.applyEditsLive, !chat.liveEditClosed else {
                return
            }
            if sourceBeforeAI == nil { sourceBeforeAI = source }
            source = code
        }
        .onChange(of: chat.liveEditClosed) { closed in
            guard closed, let code = chat.liveEdit, chat.configuration.applyEditsLive else { return }
            if sourceBeforeAI == nil { sourceBeforeAI = source }
            source = code
        }
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.caption2)
                    .foregroundStyle(VSCode.keyword)
                Text(tabTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(VSCode.text)
                    .lineLimit(1)
                Circle()
                    .fill(VSCode.dimText)
                    .frame(width: 5, height: 5)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VSCode.tabActive)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(VSCode.statusBar)
                    .frame(height: 1.5)
            }

            Menu {
                Section("Exemplos") {
                    ForEach(GooseExample.all) { example in
                        Button(example.name) {
                            source = example.source
                            openFile = nil
                            github.forgetOpenFile()
                            sourceBeforeAI = nil
                            output = ""
                            status = .idle
                        }
                    }
                }

                Section("GitHub") {
                    Button {
                        if github.isConfigured { showingBrowser = true } else { showingGitHubSettings = true }
                    } label: {
                        Label("Abrir do GitHub", systemImage: "arrow.down.doc")
                    }

                    Button {
                        showingCommit = true
                    } label: {
                        Label("Commitar", systemImage: "arrow.up.doc")
                    }
                    .disabled(!github.isConfigured)

                    Button {
                        showingGitHubSettings = true
                    } label: {
                        Label(
                            github.login.map { "Conta: \($0)" } ?? "Conectar ao GitHub",
                            systemImage: "person.badge.key"
                        )
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 36, height: 34)
                    .foregroundStyle(VSCode.dimText)
            }
            .background(VSCode.tabInactive)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(VSCode.panelBorder).frame(height: 0.5)
        }
    }

    private var tabTitle: String {
        if let openFile {
            return (openFile.path as NSString).lastPathComponent
        }
        return "main.goose"
    }

    // MARK: - Editor

    private var editor: some View {
        GooseCodeEditor(text: $source)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Output panel

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("SAÍDA")
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(VSCode.text)
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(VSCode.statusBar).frame(height: 1.5)
                    }

                Circle()
                    .fill(status.color)
                    .frame(width: 6, height: 6)

                Text(status.label)
                    .font(.caption2)
                    .foregroundStyle(VSCode.faintText)

                if let elapsed, status == .ok {
                    Text(String(format: "%.0f ms", elapsed * 1000))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(VSCode.faintText)
                }

                Spacer()

                if !output.isEmpty {
                    Button {
                        UIPasteboard.general.string = output
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copiar saída")
                }

                Button {
                    output = ""
                    status = .idle
                    elapsed = nil
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Limpar saída")

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showOutput = false }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel("Recolher a saída")
            }
            .font(.footnote)
            .foregroundStyle(VSCode.dimText)
            .padding(.horizontal, 12)

            ScrollView {
                Text(output.isEmpty ? "Toque em ▶ para rodar seu programa." : output)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(
                        output.isEmpty ? VSCode.faintText : (status == .failure ? VSCode.error : VSCode.text)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 70, maxHeight: 170)
            .accessibilityIdentifier("programOutput")
        }
        .background(VSCode.sidebar)
        .overlay(alignment: .top) {
            Rectangle().fill(VSCode.panelBorder).frame(height: 0.5)
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            Label(openFile?.repository ?? "Goose", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .lineLimit(1)

            if let openFile {
                Text(openFile.branch)
                    .lineLimit(1)
            }

            Spacer()

            Text(chat.isStreaming ? "agente escrevendo…" : "\(lineCount) linhas")
                .lineLimit(1)

            Text("Goose")
                .fontWeight(.semibold)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(VSCode.statusBar)
    }

    private var lineCount: Int {
        source.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    // MARK: - Activity bar

    private var activityBar: some View {
        HStack(spacing: 4) {
            ActivityButton(
                systemImage: "doc.badge.plus",
                label: "Novo arquivo",
                action: { newFile() }
            )

            ActivityButton(
                systemImage: "arrow.down.doc",
                label: "Abrir do GitHub",
                action: {
                    if github.isConfigured { showingBrowser = true } else { showingGitHubSettings = true }
                }
            )

            Spacer(minLength: 0)

            Button {
                dismissKeyboard()
                runProgram()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 34)
                    .background(isRunning ? VSCode.faintText : VSCode.statusBar)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .disabled(isRunning)
            .accessibilityIdentifier("runProgram")
            .accessibilityLabel("Executar")

            Spacer(minLength: 0)

            ActivityButton(
                systemImage: "sparkle",
                label: "Agente",
                isActive: showingChat,
                badge: chat.isStreaming ? 1 : nil,
                action: { showingChat = true }
            )

            ActivityButton(
                systemImage: showOutput ? "rectangle.bottomthird.inset.filled" : "rectangle.bottomthird.inset",
                label: showOutput ? "Recolher saída" : "Mostrar saída",
                isActive: showOutput,
                action: {
                    withAnimation(.easeInOut(duration: 0.15)) { showOutput.toggle() }
                }
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(VSCode.activityBar)
        .overlay(alignment: .top) {
            Rectangle().fill(VSCode.panelBorder).frame(height: 0.5)
        }
    }

    // MARK: - Actions

    private func newFile() {
        source = """
        fn main() {
            print("novo programa");
        }
        """
        openFile = nil
        github.forgetOpenFile()
        sourceBeforeAI = nil
        output = ""
        status = .idle
    }

    private func undoAIEdit() {
        guard let snapshot = sourceBeforeAI else { return }
        source = snapshot
        sourceBeforeAI = nil
    }

    /// Saves after a pause in typing, not on every keystroke.
    private func scheduleSave(_ text: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            GooseDraft.save(text)
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func runProgram() {
        guard !isRunning else { return }
        let program = source
        isRunning = true
        status = .idle
        output = ""
        elapsed = nil

        Task {
            let started = Date()
            let result = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
                do {
                    return .success(try GooseInterpreter().run(program))
                } catch {
                    return .failure(error)
                }
            }.value
            let duration = Date().timeIntervalSince(started)

            switch result {
            case let .success(text):
                output = text.isEmpty ? "(sem saída)" : text
                status = .ok
                elapsed = duration
            case let .failure(error):
                output = "Erro: \(error.localizedDescription)"
                status = .failure
            }
            isRunning = false
            showOutput = true
        }
    }
}

#Preview {
    ContentView()
}
