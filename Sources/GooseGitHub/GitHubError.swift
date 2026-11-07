import Foundation

/// Failures a GitHub call can end in, worded for the app's reader.
public enum GitHubError: Error, Equatable, LocalizedError {
    case missingToken
    case unauthorized
    case forbidden(reason: String?)
    case notFound(what: String)
    case rateLimited(reset: Date?)
    case conflict
    case unexpectedResponse
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Informe um token do GitHub nas configurações."
        case .unauthorized:
            return "Token inválido ou expirado. Gere outro em GitHub → Settings → Developer settings → Tokens."
        case let .forbidden(reason):
            return reason ?? "O token não tem permissão para esta operação."
        case let .notFound(what):
            return "Não encontrado: \(what). Confira o nome e se o token tem acesso ao repositório."
        case let .rateLimited(reset):
            guard let reset else {
                return "Limite de requisições do GitHub atingido. Tente mais tarde."
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "Limite de requisições do GitHub atingido. Libera às \(formatter.string(from: reset))."
        case .conflict:
            return "O arquivo mudou no GitHub depois que você abriu. Recarregue antes de commitar."
        case .unexpectedResponse:
            return "Resposta inesperada do GitHub."
        case let .decoding(detail):
            return "Não consegui ler a resposta do GitHub: \(detail)"
        }
    }

    /// Maps a status code to the closest readable failure.
    static func from(status: Int, headers: [String: String], what: String) -> GitHubError {
        switch status {
        case 401:
            return .unauthorized
        case 403, 429:
            if headers["x-ratelimit-remaining"] == "0" {
                let reset = headers["x-ratelimit-reset"].flatMap(Double.init)
                    .map { Date(timeIntervalSince1970: $0) }
                return .rateLimited(reset: reset)
            }
            return .forbidden(reason: nil)
        case 404:
            return .notFound(what: what)
        case 409, 422:
            return .conflict
        default:
            return .unexpectedResponse
        }
    }
}
