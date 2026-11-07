import Foundation

/// Recursive-descent parser for the supported Goose subset.
struct GooseParser {
    private static let unsupportedDeclarations: Set<String> = ["struct", "enum", "import", "const"]

    private let tokens: [GooseToken]
    private var index = 0
    private var loopDepth = 0

    init(tokens: [GooseToken]) {
        self.tokens = tokens
    }

    mutating func parseProgram() throws -> GooseProgram {
        var functions: [String: GooseFunction] = [:]
        var statements: [GooseStatement] = []

        while !isAtEnd {
            if let keyword = currentKeyword, Self.unsupportedDeclarations.contains(keyword) {
                throw syntaxError("'\(keyword)' ainda não é suportado neste app")
            }
            if currentKeyword == "fn" || currentKeyword == "recursive" {
                let function = try parseFunction()
                functions[function.name] = function
            } else {
                statements.append(try parseStatement())
            }
        }

        return GooseProgram(functions: functions, statements: statements)
    }

    // MARK: - Declarations

    private mutating func parseFunction() throws -> GooseFunction {
        let line = current.line
        // Goose requires `recursive fn` before a cycle of calls; the
        // interpreter does not need the marker but accepts it.
        if currentKeyword == "recursive" {
            advance()
        }
        try consumeKeyword("fn")
        let name = try consumeName()

        try consumeSymbol("(")
        var parameters: [String] = []
        if !isSymbol(")") {
            repeat {
                parameters.append(try consumeName())
                if isSymbol(":") {
                    try skipTypeAnnotation()
                }
            } while consumeSymbolIf(",")
        }
        try consumeSymbol(")")

        if consumeSymbolIf("->") {
            // Return types are the real compiler's business; the interpreter
            // infers values dynamically and only skips the annotation here.
            while !isSymbol("{"), !isAtEnd {
                advance()
            }
        }

        let body = try parseBlock()
        return GooseFunction(name: name, parameters: parameters, body: body, line: line)
    }

    // MARK: - Statements

    private mutating func parseStatement() throws -> GooseStatement {
        guard !isAtEnd else {
            throw syntaxError("Fim inesperado do programa")
        }

        switch currentKeyword {
        case "let", "var":
            return try parseDeclaration()
        case "while":
            return try parseWhile()
        case "for":
            return try parseForEach()
        case "return":
            return try parseReturn()
        case "break":
            let line = current.line
            guard loopDepth > 0 else {
                throw syntaxError("'break' só pode ser usado dentro de um laço")
            }
            advance()
            try consumeSymbol(";")
            return .breakLoop(line: line)
        case "continue":
            let line = current.line
            guard loopDepth > 0 else {
                throw syntaxError("'continue' só pode ser usado dentro de um laço")
            }
            advance()
            try consumeSymbol(";")
            return .continueLoop(line: line)
        case "fn", "recursive":
            throw syntaxError("Funções só podem ser declaradas no nível superior")
        default:
            return try parseExpressionStatement()
        }
    }

    private mutating func parseDeclaration() throws -> GooseStatement {
        let line = current.line
        let mutable = currentKeyword == "var"
        advance()

        let name = try consumeName()
        var typeName: String?
        if isSymbol(":") {
            typeName = try parseTypeName()
        }
        try consumeSymbol("=")
        let value = try parseExpression()
        try consumeSymbol(";")
        return .declare(name: name, mutable: mutable, typeName: typeName, value: value, line: line)
    }

    private mutating func parseWhile() throws -> GooseStatement {
        let line = current.line
        try consumeKeyword("while")
        let condition = try parseExpression()

        loopDepth += 1
        let body = try parseBlock()
        loopDepth -= 1

        return .loopWhile(condition, body, line: line)
    }

    private mutating func parseForEach() throws -> GooseStatement {
        let line = current.line
        try consumeKeyword("for")
        let name = try consumeName()
        try consumeKeyword("in")
        let iterable = try parseExpression()

        loopDepth += 1
        let body = try parseBlock()
        loopDepth -= 1

        return .forEach(name: name, iterable: iterable, body: body, line: line)
    }

    private mutating func parseReturn() throws -> GooseStatement {
        let line = current.line
        try consumeKeyword("return")
        if consumeSymbolIf(";") {
            return .returnValue(nil, line: line)
        }
        let value = try parseExpression()
        try consumeSymbol(";")
        return .returnValue(value, line: line)
    }

    private mutating func parseExpressionStatement() throws -> GooseStatement {
        let expression = try parseExpression()

        if let op = assignmentOperator {
            advance()
            let value = try parseExpression()
            try consumeSymbol(";")
            guard isAssignable(expression) else {
                throw GooseInterpreterError.syntax(
                    line: expression.line,
                    message: "Não é possível atribuir a esta expressão"
                )
            }
            return .assign(target: expression, op: op, value: value, line: expression.line)
        }

        if isSymbol("++") || isSymbol("--") {
            let op = isSymbol("++") ? "+=" : "-="
            advance()
            try consumeSymbol(";")
            guard isAssignable(expression) else {
                throw GooseInterpreterError.syntax(
                    line: expression.line,
                    message: "Não é possível atribuir a esta expressão"
                )
            }
            let one = GooseExpression.integer("1", line: expression.line)
            return .assign(target: expression, op: op, value: one, line: expression.line)
        }

        // A block or an `if` chain stands on its own, and the trailing
        // expression of a block needs no semicolon; every other expression
        // statement ends with one, as in Goose.
        if needsTerminator(expression), !isSymbol("}"), !isAtEnd {
            try consumeSymbol(";")
        }
        return .expression(expression)
    }

    private func isAssignable(_ expression: GooseExpression) -> Bool {
        switch expression {
        case .variable, .index, .field:
            return true
        default:
            return false
        }
    }

    private func needsTerminator(_ expression: GooseExpression) -> Bool {
        switch expression {
        case .conditional, .block:
            return false
        default:
            return true
        }
    }

    private var assignmentOperator: String? {
        guard case let .symbol(symbol) = current.kind else { return nil }
        return ["=", "+=", "-=", "*=", "/=", "%="].contains(symbol) ? symbol : nil
    }

    // MARK: - Expressions

    private mutating func parseExpression() throws -> GooseExpression {
        try parseBinary(minimumPrecedence: 1)
    }

    private mutating func parseBinary(minimumPrecedence: Int) throws -> GooseExpression {
        var left = try parseUnary()

        while let (precedence, symbol) = binaryOperator, precedence >= minimumPrecedence {
            advance()
            let right = try parseBinary(minimumPrecedence: precedence + 1)
            left = .binary(symbol, left, right, line: left.line)
        }
        return left
    }

    private var binaryOperator: (precedence: Int, symbol: String)? {
        guard case let .symbol(symbol) = current.kind else { return nil }
        let precedence: Int
        switch symbol {
        case "||": precedence = 1
        case "&&": precedence = 2
        case "==", "!=": precedence = 3
        case "<", "<=", ">", ">=": precedence = 4
        case "+", "-": precedence = 5
        case "*", "/", "%": precedence = 6
        default: return nil
        }
        return (precedence, symbol)
    }

    private mutating func parseUnary() throws -> GooseExpression {
        if case let .symbol(symbol) = current.kind, ["-", "!", "+"].contains(symbol) {
            let line = current.line
            advance()
            return .unary(symbol, try parseUnary(), line: line)
        }
        return try parsePostfix()
    }

    private mutating func parsePostfix() throws -> GooseExpression {
        var expression = try parsePrimary()

        while true {
            if consumeSymbolIf("[") {
                let indexExpression = try parseExpression()
                try consumeSymbol("]")
                expression = .index(expression, indexExpression, line: expression.line)
            } else if consumeSymbolIf(".") {
                let name = try consumeName()
                if consumeSymbolIf("(") {
                    expression = .method(expression, name, try parseArguments(), line: expression.line)
                } else {
                    expression = .field(expression, name, line: expression.line)
                }
            } else if consumeKeywordIf("as") {
                // The interpreter truncates like a release build; `as!` is
                // accepted as the same operation.
                _ = consumeSymbolIf("!")
                expression = .cast(expression, try parseTypeName(), checked: false, line: expression.line)
            } else {
                break
            }
        }

        return expression
    }

    private mutating func parseArguments() throws -> [GooseExpression] {
        var arguments: [GooseExpression] = []
        if !isSymbol(")") {
            repeat {
                arguments.append(try parseExpression())
            } while consumeSymbolIf(",")
        }
        try consumeSymbol(")")
        return arguments
    }

    private mutating func parsePrimary() throws -> GooseExpression {
        let token = current

        switch token.kind {
        case let .integer(text):
            advance()
            return .integer(text, line: token.line)

        case let .double(text):
            advance()
            guard let value = Double(text) else {
                throw GooseInterpreterError.syntax(line: token.line, message: "Número inválido: \(text)")
            }
            return .double(value, line: token.line)

        case let .string(value):
            advance()
            return .string(value, line: token.line)

        case let .keyword(keyword):
            switch keyword {
            case "true", "false":
                advance()
                return .boolean(keyword == "true", line: token.line)
            case "null":
                advance()
                return .null(line: token.line)
            case "if":
                return try parseConditional()
            default:
                throw GooseInterpreterError.syntax(
                    line: token.line,
                    message: "Expressão inesperada: \(keyword)"
                )
            }

        case let .identifier(name):
            advance()
            if consumeSymbolIf("(") {
                return .call(name, try parseArguments(), line: token.line)
            }
            return .variable(name, line: token.line)

        case .symbol("("):
            advance()
            let expression = try parseExpression()
            try consumeSymbol(")")
            return expression

        case .symbol("["):
            return try parseArrayLiteral(line: token.line)

        case .symbol("{"):
            return .block(try parseBlock(), line: token.line)

        case .symbol:
            throw GooseInterpreterError.syntax(
                line: token.line,
                message: "Expressão inesperada: \(symbolText)"
            )

        case .end:
            throw syntaxError("Fim inesperado do programa")
        }
    }

    private mutating func parseArrayLiteral(line: Int) throws -> GooseExpression {
        advance()
        var elements: [GooseExpression] = []

        if !isSymbol("]") {
            let first = try parseExpression()
            if consumeSymbolIf(";") {
                // `[value; count]` is Goose's fill form.
                let count = try parseExpression()
                try consumeSymbol("]")
                return .arrayFill(first, count, line: line)
            }
            elements.append(first)
            while consumeSymbolIf(",") {
                if isSymbol("]") { break }
                elements.append(try parseExpression())
            }
        }

        try consumeSymbol("]")
        return .arrayLiteral(elements, line: line)
    }

    private mutating func parseConditional() throws -> GooseExpression {
        let line = current.line
        try consumeKeyword("if")
        let condition = try parseExpression()
        let thenBody = try parseBlock()

        var elseBody: [GooseStatement]?
        if consumeKeywordIf("else") {
            if currentKeyword == "if" {
                elseBody = [.expression(try parseConditional())]
            } else {
                elseBody = try parseBlock()
            }
        }

        return .conditional(condition, thenBody, elseBody, line: line)
    }

    // MARK: - Blocks and types

    private mutating func parseBlock() throws -> [GooseStatement] {
        try consumeSymbol("{")
        var statements: [GooseStatement] = []
        while !isSymbol("}") {
            guard !isAtEnd else {
                throw syntaxError("Bloco sem fechamento")
            }
            statements.append(try parseStatement())
        }
        try consumeSymbol("}")
        return statements
    }

    /// Reads a type annotation such as `u8`, `f64` or `i64[>..]`.
    private mutating func parseTypeName() throws -> String {
        if isSymbol(":") {
            advance()
        }
        var parts: [String] = []
        var depth = 0

        while !isAtEnd {
            if depth == 0, isSymbol("=") || isSymbol(";") || isSymbol(",") || isSymbol(")") || isSymbol("{") {
                break
            }
            switch current.kind {
            case let .symbol(symbol):
                if symbol == "[" { depth += 1 }
                if symbol == "]" { depth -= 1 }
                parts.append(symbol)
            case let .identifier(name):
                parts.append(name)
            case let .keyword(word):
                parts.append(word)
            case let .integer(text), let .double(text):
                parts.append(text)
            case .string, .end:
                break
            }
            advance()
        }

        guard !parts.isEmpty else {
            throw syntaxError("Tipo esperado após ':'")
        }
        return parts.joined()
    }

    private mutating func skipTypeAnnotation() throws {
        try consumeSymbol(":")
        var depth = 0
        while !isAtEnd {
            if depth == 0, isSymbol(",") || isSymbol(")") || isSymbol("{") {
                break
            }
            if isSymbol("[") { depth += 1 }
            if isSymbol("]") { depth -= 1 }
            advance()
        }
    }

    // MARK: - Token helpers

    private var current: GooseToken {
        tokens[index]
    }

    private var symbolText: String {
        if case let .symbol(symbol) = current.kind { return symbol }
        return "\(current.kind)"
    }

    private var currentKeyword: String? {
        if case let .keyword(keyword) = current.kind { return keyword }
        return nil
    }

    private var isAtEnd: Bool {
        if case .end = current.kind { return true }
        return false
    }

    private func isSymbol(_ symbol: String) -> Bool {
        current.kind == .symbol(symbol)
    }

    private mutating func advance() {
        if !isAtEnd {
            index += 1
        }
    }

    private mutating func consumeSymbol(_ symbol: String) throws {
        guard isSymbol(symbol) else {
            throw syntaxError("Esperado '\(symbol)'")
        }
        advance()
    }

    private mutating func consumeSymbolIf(_ symbol: String) -> Bool {
        guard isSymbol(symbol) else { return false }
        advance()
        return true
    }

    private mutating func consumeKeyword(_ keyword: String) throws {
        guard currentKeyword == keyword else {
            throw syntaxError("Esperado '\(keyword)'")
        }
        advance()
    }

    private mutating func consumeKeywordIf(_ keyword: String) -> Bool {
        guard currentKeyword == keyword else { return false }
        advance()
        return true
    }

    private mutating func consumeName() throws -> String {
        guard case let .identifier(name) = current.kind else {
            throw syntaxError("Nome esperado")
        }
        advance()
        return name
    }

    private func syntaxError(_ message: String) -> GooseInterpreterError {
        .syntax(line: current.line, message: message)
    }
}
