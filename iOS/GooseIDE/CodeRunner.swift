import Foundation
import SwiftUI

struct CodeRunnerResult {
    let output: String
    let succeeded: Bool
}

enum CodeRunnerError: LocalizedError {
    case missingLanguage
    case invalidEndpoint
    case insecureEndpoint
    case invalidResponse
    case service(String)

    var errorDescription: String? {
        switch self {
        case .missingLanguage:
            return "Esta linguagem não tem um runner remoto configurado."
        case .invalidEndpoint:
            return "Informe um endereço base válido para o servidor Piston."
        case .insecureEndpoint:
            return "Use HTTPS fora da rede local."
        case .invalidResponse:
            return "O servidor retornou uma resposta que o app não reconhece."
        case let .service(message):
            return message
        }
    }
}

enum PistonCodeRunner {
    static func execute(
        source: String,
        language: CodeLanguage,
        endpoint: String
    ) async throws -> CodeRunnerResult {
        guard let pistonLanguage = language.pistonLanguage else {
            throw CodeRunnerError.missingLanguage
        }

        let url = try executeURL(baseAddress: endpoint)
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(ExecuteRequest(
            language: pistonLanguage,
            version: "*",
            files: [ExecuteFile(name: "main.\(language.fileExtension)", content: source)],
            stdin: "",
            args: [],
            compile_timeout: 10_000,
            run_timeout: 3_000
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodeRunnerError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServiceError.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw CodeRunnerError.service(message)
        }

        let result = try JSONDecoder().decode(ExecuteResponse.self, from: data)
        guard result.compile != nil || result.run != nil else {
            throw CodeRunnerError.invalidResponse
        }

        var sections: [String] = []
        if let compile = result.compile {
            let text = compile.displayOutput
            if !text.isEmpty {
                sections.append("[compilação]\n\(text)")
            }
        }
        if let run = result.run {
            let text = run.displayOutput
            if !text.isEmpty {
                sections.append(text)
            }
            if let status = run.status {
                sections.append("[\(status)] \(run.message ?? "Execução interrompida.")")
            }
            if let code = run.code, code != 0 {
                sections.append("Processo encerrado com código \(code).")
            }
        }

        let succeeded = result.compile?.status == nil
            && (result.compile?.code ?? 0) == 0
            && result.run?.status == nil
            && result.run?.code == 0
        return CodeRunnerResult(
            output: sections.isEmpty ? "(sem saída)" : sections.joined(separator: "\n"),
            succeeded: succeeded
        )
    }

    private static func executeURL(baseAddress: String) throws -> URL {
        let trimmed = baseAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              ["http", "https"].contains(scheme),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw CodeRunnerError.invalidEndpoint
        }

        if scheme == "http", !isLocalHost(host) {
            throw CodeRunnerError.insecureEndpoint
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, "api/v2/execute"].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url else { throw CodeRunnerError.invalidEndpoint }
        return url
    }

    private static func isLocalHost(_ host: String) -> Bool {
        host == "localhost"
            || host == "::1"
            || host.hasSuffix(".local")
            || host.hasPrefix("127.")
            || host.hasPrefix("10.")
            || host.hasPrefix("192.168.")
            || (host.hasPrefix("172.") && isPrivate172Address(host))
    }

    private static func isPrivate172Address(_ host: String) -> Bool {
        guard let secondOctet = host.split(separator: ".").dropFirst().first,
              let value = Int(secondOctet) else {
            return false
        }
        return (16...31).contains(value)
    }
}

private struct ExecuteRequest: Encodable {
    let language: String
    let version: String
    let files: [ExecuteFile]
    let stdin: String
    let args: [String]
    let compile_timeout: Int
    let run_timeout: Int
}

private struct ExecuteFile: Encodable {
    let name: String
    let content: String
}

private struct ExecuteResponse: Decodable {
    let compile: ExecuteStage?
    let run: ExecuteStage?
}

private struct ExecuteStage: Decodable {
    let stdout: String?
    let stderr: String?
    let output: String?
    let code: Int?
    let status: String?
    let message: String?

    var displayOutput: String {
        if let output, !output.isEmpty { return output }
        return [stdout, stderr].compactMap { $0 }.filter { !$0.isEmpty }.joined()
    }
}

private struct ServiceError: Decodable {
    let message: String?
}

struct CodeRunnerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("goose.piston.baseURL") private var endpoint = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Servidor Piston") {
                    TextField("http://192.168.1.20:2000", text: $endpoint)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }

                Section {
                    Text("C e NASM x86-64 são enviados a este servidor para compilação e execução. Goose continua local. Use um servidor que você controla; HTTPS é obrigatório fora da rede local.")
                        .font(.footnote)
                        .foregroundStyle(VSCode.dimText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(VSCode.editorBackground)
            .navigationTitle("Runner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluído") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}