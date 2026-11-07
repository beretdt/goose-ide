import Foundation

/// A lexical token produced by `GooseLexer`.
enum GooseTokenKind: Equatable {
    case identifier(String)
    case keyword(String)
    case integer(String)
    case double(String)
    case string(String)
    case symbol(String)
    case end
}

struct GooseToken: Equatable {
    let kind: GooseTokenKind
    let line: Int
}

enum GooseKeyword {
    static let all: Set<String> = [
        "fn", "recursive", "let", "var", "if", "else", "while", "for", "in", "return",
        "true", "false", "break", "continue", "as", "null", "match",
        "struct", "enum", "import", "const",
    ]
}

/// Multi-character symbols are matched before single-character ones.
enum GooseSymbol {
    static let all: [String] = [
        "->", "=>", "==", "!=", "<=", ">=", "&&", "||",
        "+=", "-=", "*=", "/=", "%=", "++", "--", "..",
        "{", "}", "(", ")", "[", "]", ",", ";", ".", ":", "+", "-",
        "*", "/", "%", "=", "<", ">", "!", "&", "|", "^", "_",
    ]
}
