import SwiftUI

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
        GooseExample(
            name: "Contagem regressiva",
            source: """
            fn main() {
                var n = 5;
                while n > 0 {
                    print(n);
                    n -= 1;
                }
                print("decolar!");
            }
            """
        ),
    ]
}

struct ContentView: View {
    @State private var source = GooseExample.all[0].source
    @State private var output = ""
    @State private var status: Status = .idle
    @State private var isRunning = false
    @FocusState private var editorFocused: Bool

    private enum Status {
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
            case .idle: return .secondary
            case .ok: return .green
            case .failure: return .red
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                editor
                Divider()
                outputPanel
            }
            .navigationTitle("Goose IDE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(GooseExample.all) { example in
                            Button(example.name) {
                                source = example.source
                                output = ""
                                status = .idle
                            }
                        }
                    } label: {
                        Label("Exemplos", systemImage: "square.stack.3d.up")
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("EDITOR")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                editorFocused = false
                runProgram()
            } label: {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 74)
                } else {
                    Label("Executar", systemImage: "play.fill")
                        .frame(width: 74)
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)
            .accessibilityIdentifier("runProgram")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var editor: some View {
        GooseCodeEditor(text: $source)
            .focused($editorFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("sourceEditor")
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("SAÍDA")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)

                Circle()
                    .fill(status.color)
                    .frame(width: 6, height: 6)
                Text(status.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if !output.isEmpty {
                    Button {
                        UIPasteboard.general.string = output
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .font(.footnote)
                    .accessibilityLabel("Copiar saída")
                }

                Button {
                    output = ""
                    status = .idle
                } label: {
                    Image(systemName: "trash")
                }
                .font(.footnote)
                .accessibilityLabel("Limpar saída")
            }

            ScrollView {
                Text(output.isEmpty ? "Toque em Executar para rodar seu programa." : output)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(output.isEmpty ? .secondary : (status == .failure ? .red : .primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 90, maxHeight: 190)
            .accessibilityIdentifier("programOutput")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08))
    }

    private func runProgram() {
        guard !isRunning else { return }
        let program = source
        isRunning = true
        status = .idle
        output = ""

        Task {
            let result: Result<String, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try GooseInterpreter().run(program))
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case let .success(text):
                output = text.isEmpty ? "(sem saída)" : text
                status = .ok
            case let .failure(error):
                output = "Erro: \(error.localizedDescription)"
                status = .failure
            }
            isRunning = false
        }
    }
}

#Preview {
    ContentView()
}
