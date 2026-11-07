import SwiftUI

struct ContentView: View {
    @State private var source = """
    fn main() {
        print("Hello, Goose!");
    }
    """
    @State private var output = "Toque em Executar para rodar seu programa."

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("EDITOR")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: runProgram) {
                        Label("Executar", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("runProgram")
                }
                .padding()

                TextEditor(text: $source)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .accessibilityIdentifier("sourceEditor")

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("SAÍDA")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(output)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 140)
                    .accessibilityIdentifier("programOutput")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.08))
            }
            .navigationTitle("Goose IDE")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func runProgram() {
        do {
            output = try GooseInterpreter().run(source)
        } catch {
            output = "Erro: \(error.localizedDescription)"
        }
    }
}
