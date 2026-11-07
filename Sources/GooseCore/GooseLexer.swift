import Foundation

/// Turns Goose source text into tokens, tracking the line of each one.
struct GooseLexer {
    private let characters: [Character]
    private var index = 0
    private var line = 1

    init(source: String) {
        characters = Array(source)
    }

    mutating func tokenize() throws -> [GooseToken] {
        var tokens: [GooseToken] = []

        while let character = current {
            if character == "\n" {
                line += 1
                advance()
                continue
            }
            if character.isWhitespace {
                advance()
                continue
            }
            if character == "/", next == "/" {
                skipLineComment()
                continue
            }
            if character == "/", next == "*" {
                try skipBlockComment()
                continue
            }

            let tokenLine = line
            if isIdentifierStart(character) {
                let word = readIdentifier()
                tokens.append(GooseToken(
                    kind: GooseKeyword.all.contains(word) ? .keyword(word) : .identifier(word),
                    line: tokenLine
                ))
            } else if character.isNumber {
                tokens.append(try readNumber(line: tokenLine))
            } else if character == "\"" {
                tokens.append(GooseToken(kind: .string(try readString()), line: tokenLine))
            } else if character == "'" {
                tokens.append(GooseToken(kind: .integer(String(try readCharacterLiteral())), line: tokenLine))
            } else if let symbol = matchSymbol() {
                tokens.append(GooseToken(kind: .symbol(symbol), line: tokenLine))
            } else {
                throw GooseInterpreterError.syntax(
                    line: tokenLine,
                    message: "Caractere inesperado: \(character)"
                )
            }
        }

        tokens.append(GooseToken(kind: .end, line: line))
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

    private mutating func skipLineComment() {
        while let character = current, character != "\n" {
            advance()
        }
    }

    private mutating func skipBlockComment() throws {
        let startLine = line
        advance()
        advance()
        while let character = current {
            if character == "*", next == "/" {
                advance()
                advance()
                return
            }
            if character == "\n" {
                line += 1
            }
            advance()
        }
        throw GooseInterpreterError.syntax(line: startLine, message: "Comentário sem fechamento")
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

    private mutating func readNumber(line tokenLine: Int) throws -> GooseToken {
        let start = index
        var isDouble = false

        while current?.isNumber == true {
            advance()
        }
        // A `.` belongs to the number only when a digit follows it, so that
        // field access and ranges keep working.
        if current == ".", next?.isNumber == true {
            isDouble = true
            advance()
            while current?.isNumber == true {
                advance()
            }
        }
        if current == "e" || current == "E" {
            let isExponent = next == "+" || next == "-" || next?.isNumber == true
            if isExponent {
                isDouble = true
                advance()
                if current == "-" || current == "+" {
                    advance()
                }
                guard current?.isNumber == true else {
                    throw GooseInterpreterError.syntax(line: tokenLine, message: "Expoente incompleto")
                }
                while current?.isNumber == true {
                    advance()
                }
            }
        }

        let text = String(characters[start..<index])
        return GooseToken(kind: isDouble ? .double(text) : .integer(text), line: tokenLine)
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
            case "0": value.append("\0")
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

    /// `'h'` is an integer, as in Goose, where a character is a byte value.
    private mutating func readCharacterLiteral() throws -> Int {
        let startLine = line
        advance()

        guard let character = current else {
            throw GooseInterpreterError.syntax(line: startLine, message: "Literal de caractere vazio")
        }
        advance()

        var value: UInt32
        if character == "\\" {
            guard let escaped = current else {
                throw GooseInterpreterError.syntax(line: startLine, message: "Literal de caractere vazio")
            }
            advance()
            switch escaped {
            case "n": value = 10
            case "r": value = 13
            case "t": value = 9
            case "0": value = 0
            case "\\": value = 92
            case "'": value = 39
            case "\"": value = 34
            default:
                throw GooseInterpreterError.syntax(
                    line: startLine,
                    message: "Escape não suportado: \(escaped)"
                )
            }
        } else {
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
                throw GooseInterpreterError.syntax(
                    line: startLine,
                    message: "Um literal de caractere deve ser um único byte"
                )
            }
            value = scalar.value
        }

        guard current == "'" else {
            throw GooseInterpreterError.syntax(line: startLine, message: "Literal de caractere sem fechamento")
        }
        advance()
        return Int(value)
    }

    private mutating func matchSymbol() -> String? {
        for symbol in GooseSymbol.all {
            var cursor = index
            var matched = true
            for expected in symbol {
                guard cursor < characters.count, characters[cursor] == expected else {
                    matched = false
                    break
                }
                cursor += 1
            }
            if matched {
                index = cursor
                return symbol
            }
        }
        return nil
    }
}
