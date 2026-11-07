import SwiftUI
import UIKit

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

/// Keeps the last program on disk, so closing the app on a phone does not
/// throw away what was being written.
private enum GooseDraft {
    private static let key = "goose.draft.source"

    static func load() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func save(_ source: String) {
        UserDefaults.standard.set(source, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct ContentView: View {
    @State private var source = GooseDraft.load() ?? GooseExample.all[0].source
    @State private var output = ""
    @State private var status: Status = .idle
    @State private var isRunning = false
    @State private var elapsed: Double?
    @State private var saveTask: Task<Void, Never>?

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

                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: source, subject: Text("Programa Goose")) {
                        Label("Compartilhar", systemImage: "square.and.arrow.up")
                    }
                }
            }
            // One-parameter form: the two-parameter `onChange` is iOS 17 only.
            .onChange(of: source) { newValue in
                scheduleSave(newValue)
            }
        }
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

    private var header: some View {
        HStack(spacing: 12) {
            Text("EDITOR")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                dismissKeyboard()
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

                if let elapsed, status == .ok {
                    Text(String(format: "%.0f ms", elapsed * 1000))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

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
                    .foregroundStyle(outputColor)
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

    private var outputColor: Color {
        if output.isEmpty { return .secondary }
        return status == .failure ? .red : .primary
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
        }
    }
}

#Preview {
    ContentView()
}
