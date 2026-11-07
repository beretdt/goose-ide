import Foundation

public struct GooseInterpreter {
    public init() {}

    public func run(_ source: String) throws -> String {
        var parser = try Parser(source: source)
        return try parser.run()
    }
}

public enum GooseInterpreterError: Error, Equatable, LocalizedError {
    case syntax(line: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case let .syntax(line, message):
            return "Linha \(line): \(message)"
        }
    }
}

private struct Token {
    enum Kind: Equatable {
        case identifier(String)
        case string(String)
        case number(String)
        case punctuation(Character)
        case end
    }

    let kind: Kind
    let line: Int
}

private struct Lexer {
    private let characters: [Character]
    private var index = 0
    private var line = 1

    init(source: String) {
        characters = Array(source)
    }

    mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []

        while let character = current {
            if character.isWhitespace {
                if character == "\n" {
                    line += 1
                }
                advance()
                continue
            }

            let tokenLine = line
            if isIdentifierStart(character) {
                tokens.append(Token(kind: .identifier(readIdentifier()), line: tokenLine))
            } else if character.isNumber || (character == "-" && next?.isNumber == true) {
                tokens.append(Token(kind: .number(readNumber()), line: tokenLine))
            } else if character == "\"" {
                tokens.append(Token(kind: .string(try readString()), line: tokenLine))
            } else if "{}(),;.".contains(character) {
                tokens.append(Token(kind: .punctuation(character), line: tokenLine))
                advance()
            } else {
                throw GooseInterpreterError.syntax(
                    line: tokenLine,
                    message: "Caractere inesperado: \(character)"
                )
            }
        }

        tokens.append(Token(kind: .end, line: line))
        return tokens
    }

    private var current: Character? {
        index < characters.count ? characters[index] : nil
    }

    private var next: Character? {
        index + 1 < characters.count ? characters[index + 1] : nil
    }

    private mutating func advance() {
        index += 1
    }

    private func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private func isIdentifierContinuation(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }

    private mutating func readIdentifier() -> String {
        let start = index
        while let character = current, isIdentifierContinuation(character) {
            advance()
        }
        return String(characters[start..<index])
    }

    private mutating func readNumber() -> String {
        let start = index
        if current == "-" {
            advance()
        }
        while current?.isNumber == true {
            advance()
        }
        if current == ".", next?.isNumber == true {
            advance()
            while current?.isNumber == true {
                advance()
            }
        }
        return String(characters[start..<index])
    }

    private mutating func readString() throws -> String {
        let stringLine = line
        advance()
        var value = ""

        while let character = current {
            advance()
            if character == "\"" {
                return value
            }
            if character == "\n" {
                line += 1
            }
            guard character == "\\" else {
                value.append(character)
                continue
            }

            guard let escaped = current else {
                break
            }
            advance()
            switch escaped {
            case "n": value.append("\n")
            case "r": value.append("\r")
            case "t": value.append("\t")
            case "\"": value.append("\"")
            case "\\": value.append("\\")
            default:
                throw GooseInterpreterError.syntax(
                    line: line,
                    message: "Escape não suportado: \(escaped)"
                )
            }
        }

        throw GooseInterpreterError.syntax(line: stringLine, message: "Texto sem aspas de fechamento")
    }
}

private struct Parser {
    private var tokens: [Token]
    private var index = 0

    init(source: String) throws {
        var lexer = Lexer(source: source)
        tokens = try lexer.tokenize()
    }

    mutating func run() throws -> String {
        var hasMainFunction = false
        if isIdentifier("fn") {
            hasMainFunction = true
            try consumeIdentifier("fn")
            try consumeIdentifier("main")
            try consumePunctuation("(")
            try consumePunctuation(")")
            try consumePunctuation("{")
        }

        var output = ""
        while !isAtEnd && !(hasMainFunction && isPunctuation("}")) {
            output += try parsePrintStatement()
        }

        if hasMainFunction {
            try consumePunctuation("}")
        }
        guard isAtEnd else {
            throw syntaxError("Conteúdo inesperado após o programa")
        }
        return output
    }

    private mutating func parsePrintStatement() throws -> String {
        try consumeIdentifier("print")
        try consumePunctuation("(")

        var values: [String] = []
        if !isPunctuation(")") {
            values.append(try parseLiteral())
            while isPunctuation(",") {
                advance()
                values.append(try parseLiteral())
            }
        }

        try consumePunctuation(")")
        try consumePunctuation(";")
        return values.joined() + "\n"
    }

    private mutating func parseLiteral() throws -> String {
        let token = current
        advance()
        switch token.kind {
        case let .string(value), let .number(value):
            return value
        case .identifier("true"):
            return "true"
        case .identifier("false"):
            return "false"
        default:
            throw GooseInterpreterError.syntax(
                line: token.line,
                message: "Esperado texto, número ou booleano"
            )
        }
    }

    private mutating func consumeIdentifier(_ expected: String) throws {
        guard isIdentifier(expected) else {
            throw syntaxError("Esperado '\(expected)'")
        }
        advance()
    }

    private mutating func consumePunctuation(_ expected: Character) throws {
        guard isPunctuation(expected) else {
            throw syntaxError("Esperado '\(expected)'")
        }
        advance()
    }

    private var current: Token {
        tokens[index]
    }

    private var isAtEnd: Bool {
        if case .end = current.kind {
            return true
        }
        return false
    }

    private func isIdentifier(_ expected: String) -> Bool {
        current.kind == .identifier(expected)
    }

    private func isPunctuation(_ expected: Character) -> Bool {
        current.kind == .punctuation(expected)
    }

    private mutating func advance() {
        if !isAtEnd {
            index += 1
        }
    }

    private func syntaxError(_ message: String) -> GooseInterpreterError {
        .syntax(line: current.line, message: message)
    }
}
