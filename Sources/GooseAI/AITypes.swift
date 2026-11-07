import Foundation

// MARK: - Provider

/// Where the chat completions come from. All three speak the same
/// OpenAI-compatible body, so only the URL and headers differ.
public enum AIProvider: String, CaseIterable, Codable, Sendable {
    /// OpenRouter: one key, most models.
    case openRouter
    /// GitHub Models: uses the github.com token, which a Copilot subscriber
    /// already has. The Copilot Chat API itself is not public.
    case gitHubModels
    /// Any OpenAI-compatible endpoint, for a proxy or a local server.
    case custom

    public var title: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .gitHubModels: return "GitHub Models"
        case .custom: return "Compatível com OpenAI"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .gitHubModels: return "https://models.github.ai/inference"
        case .custom: return "http://localhost:11434/v1"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openRouter: return "anthropic/claude-sonnet-4"
        case .gitHubModels: return "openai/gpt-4o"
        case .custom: return "gpt-4o-mini"
        }
    }

    /// A short hint under the field, so the setup is not guesswork.
    public var keyHint: String {
        switch self {
        case .openRouter:
            return "Chave em openrouter.ai/keys, começa com sk-or-."
        case .gitHubModels:
            return "Use o mesmo token do GitHub (fine-grained sem escopo, ou clássico com models:read)."
        case .custom:
            return "O servidor precisa aceitar POST /chat/completions no formato OpenAI."
        }
    }
}

// MARK: - Configuration

public struct AIConfiguration: Codable, Equatable, Sendable {
    public var provider: AIProvider
    public var model: String
    public var baseURL: String
    public var systemPrompt: String
    public var temperature: Double
    public var maxTokens: Int
    /// Ask the model to answer with the whole file in a ```goose block, which
    /// is what lets the app apply the edit while it is still streaming.
    public var applyEditsLive: Bool

    public init(
        provider: AIProvider = .openRouter,
        model: String = AIProvider.openRouter.defaultModel,
        baseURL: String = AIProvider.openRouter.defaultBaseURL,
        systemPrompt: String = AIConfiguration.defaultSystemPrompt,
        temperature: Double = 0.2,
        maxTokens: Int = 2_048,
        applyEditsLive: Bool = true
    ) {
        self.provider = provider
        self.model = model
        self.baseURL = baseURL
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.applyEditsLive = applyEditsLive
    }

    /// Switching provider moves the defaults with it, keeping any custom URL.
    public mutating func select(_ provider: AIProvider) {
        self.provider = provider
        model = provider.defaultModel
        if provider != .custom || baseURL.isEmpty {
            baseURL = provider.defaultBaseURL
        }
    }

    public var chatCompletionsURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/chat/completions"),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    /// The prompt the app ships with: it describes the subset the interpreter
    /// actually runs, so the model does not write code the app cannot execute.
    public static let defaultSystemPrompt = """
    Você é o agente de código do Goose IDE, um app de iPhone que interpreta um \
    subconjunto da linguagem Goose. Você edita o programa do usuário.

    Regras de resposta:
    - Quando precisar alterar o programa, responda com o arquivo COMPLETO dentro \
    de um único bloco ```goose. Sem trechos parciais, sem "...", sem comentários \
    dizendo para o usuário completar.
    - Fora do bloco, escreva no máximo três frases curtas explicando o que mudou.
    - Se a pergunta não pedir mudança de código, responda só em texto.

    O que o interpretador aceita hoje:
    - `fn` e `recursive fn` (obrigatório antes de recursão), `let`/`var`,
      `return`, `break`, `continue`, `while`, `loop { }`, `for i in n`,
      `for i in a..b`, `for x in array` e `for &x in array` (com escrita de
      volta no array).
    - `if`/`else if`/`else`, `block { }`, `guard c;`, `guard c else { … }`
      e `defer`.
    - `match` como expressão, com bind do payload (`Circle c => c.r`), várias
      variantes por braço, constantes, faixas (`1..50`) e `_`.
    - Vários resultados: `fn f() -> i64, bool` com `return a, b;` e
      `let x, y = f();`.
    - Optionais simples: `i64?` no retorno, com `null`, comparáveis por
      `==` e `!=`.
    - Operadores `+ - * / %`, comparações, `&&`, `||`, `!`; a aritmética
      mantém a largura do tipo (`u8 + 42` estoura em 8 bits) e `as`/`as!`
      convertem.
    - `struct` com campos tipados e valores padrão, literais por nome ou
      posição, leitura e atribuição de campo; `enum` com e sem payload.
    - Arrays `i64[>..]`, `[7, 8, 9]`, slices `a[1..4]`, `a[^2..]`, `a[..]`,
      `.len`, `.cap`, `push`, `pop`, `append`.
    - `print(...)` para tudo, `str(...)` para texto e `format(array, …)` para
      escrever em um array de bytes. `u8[>..]` é texto.

    Não use: `import`, biblioteca padrão (std, sort, vetores prontos), enum em
    modo variável (`Shape..`), referências com dono (`T&`), nem funções que
    não estejam nesta lista. Se o pedido exigir algo assim, diga em uma frase
    e ofereça o equivalente com o que existe.

    Não invente funções da biblioteca padrão. Prefira código simples, com
    `print` para mostrar resultados, e nomes em português quando fizer sentido.
    """
}

// MARK: - Messages

public struct AIChatMessage: Codable, Equatable, Identifiable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public let id: UUID
    public var role: Role
    public var content: String

    public init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

// MARK: - Errors

public enum AIError: Error, Equatable, LocalizedError {
    case missingKey
    case invalidURL
    case unauthorized(String?)
    case rateLimited(String?)
    case http(status: Int, message: String)
    case emptyReply

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Falta a chave da API. Abra as configurações do chat e informe uma."
        case .invalidURL:
            return "A URL base do provedor não é válida."
        case let .unauthorized(detail):
            return detail ?? "A chave foi recusada pelo provedor."
        case let .rateLimited(detail):
            return detail ?? "Limite do provedor atingido. Tente de novo em instantes."
        case let .http(status, message):
            return "O provedor respondeu \(status): \(message)"
        case .emptyReply:
            return "O modelo não devolveu texto."
        }
    }

    /// Pulls the provider's own message out of an error body, which is far
    /// more useful than the status code alone.
    static func from(status: Int, body: String) -> AIError {
        let detail = Self.message(in: body)
        switch status {
        case 401, 403:
            return .unauthorized(detail)
        case 429:
            return .rateLimited(detail)
        default:
            return .http(status: status, message: detail ?? body.prefix(300).description)
        }
    }

    private static func message(in body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = json["error"] as? [String: Any] {
            return error["message"] as? String
        }
        return json["message"] as? String
    }
}
