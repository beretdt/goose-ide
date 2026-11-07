import Foundation

/// Recursive-descent parser for the supported Goose subset.
struct GooseParser {
    private static let unsupportedDeclarations: Set<String> = ["import", "const"]

    /// Deeply nested source recurses deeply in the parser, and a phone's
    /// thread stacks are small, so nesting is capped rather than left to crash.
    private static let nestingLimit = 200

    private let tokens: [GooseToken]
    private let structNames: Set<String>
    private let enumNames: Set<String>
    private var index = 0
    /// `break` needs a loop or a block to leave; the two are tracked apart.
    private var loopDepth = 0
    private var blockDepth = 0
    private var nesting = 0

    init(tokens: [GooseToken]) {
        self.tokens = tokens
        let declared = Self.declaredTypes(in: tokens)
        structNames = declared.structs
        enumNames = declared.enums
    }

    /// A first pass over the tokens, so a literal can mention a type declared
    /// further down the file.
    private static func declaredTypes(in tokens: [GooseToken])
        -> (structs: Set<String>, enums: Set<String>) {
        var structs: Set<String> = []
        var enums: Set<String> = []

        for (position, token) in tokens.enumerated() {
            guard case let .keyword(word) = token.kind, word == "struct" || word == "enum" else {
                continue
            }
            let next = position + 1
            guard next < tokens.count, case let .identifier(name) = tokens[next].kind else {
                continue
            }
            if word == "struct" { structs.insert(name) } else { enums.insert(name) }
        }

        return (structs, enums)
    }

    mutating func parseProgram() throws -> GooseProgram {
        var functions: [String: GooseFunction] = [:]
        var structs: [String: GooseStructDecl] = [:]
        var enums: [String: GooseEnumDecl] = [:]
        var statements: [GooseStatement] = []

        while !isAtEnd {
            switch currentKeyword {
            case "struct":
                let declaration = try parseStructDeclaration()
                structs[declaration.name] = declaration
            case "enum":
                let declaration = try parseEnumDeclaration()
                enums[declaration.name] = declaration
            case "fn", "recursive":
                let function = try parseFunction()
                functions[function.name] = function
            case let keyword? where Self.unsupportedDeclarations.contains(keyword):
                throw syntaxError("'\(keyword)' ainda não é suportado neste app")
            default:
                statements.append(try parseStatement())
            }
        }

        return GooseProgram(
            functions: functions,
            structs: structs,
            enums: enums,
            statements: statements
        )
    }

    // MARK: - Declarations

    private mutating func parseStructDeclaration() throws -> GooseStructDecl {
        let line = current.line
        try consumeKeyword("struct")
        let name = try consumeName()
        let fields = try parseFieldList()
        return GooseStructDecl(name: name, fields: fields, line: line)
    }

    private mutating func parseEnumDeclaration() throws -> GooseEnumDecl {
        let line = current.line
        try consumeKeyword("enum")
        let name = try consumeName()
        try consumeSymbol("{")

        var variants: [GooseVariantDecl] = []
        while !isSymbol("}") {
            let variantName = try consumeName()
            var fields: [GooseFieldDecl] = []
            if isSymbol("{") {
                fields = try parseFieldList()
            } else if consumeSymbolIf("(") {
                // The tuple form writes the payload types only.
                var position = 0
                while !isSymbol(")") {
                    _ = try parseTypeName()
                    fields.append(GooseFieldDecl(name: "\(position)", typeName: nil, defaultValue: nil))
                    position += 1
                    _ = consumeSymbolIf(",")
                }
                try consumeSymbol(")")
            }
            variants.append(GooseVariantDecl(name: variantName, fields: fields))
            _ = consumeSymbolIf(",")
        }

        try consumeSymbol("}")
        return GooseEnumDecl(name: name, variants: variants, line: line)
    }

    private mutating func parseFieldList() throws -> [GooseFieldDecl] {
        try consumeSymbol("{")
        var fields: [GooseFieldDecl] = []

        while !isSymbol("}") {
            let name = try consumeName()
            var typeName: String?
            if isSymbol(":") {
                typeName = try parseTypeName()
            }
            var defaultValue: GooseExpression?
            if consumeSymbolIf("=") {
                defaultValue = try parseExpression()
            }
            fields.append(GooseFieldDecl(name: name, typeName: typeName, defaultValue: defaultValue))
            _ = consumeSymbolIf(",")
        }

        try consumeSymbol("}")
        return fields
    }

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
        case "loop":
            return try parseLoopForever()
        case "for":
            return try parseForEach()
        case "return":
            return try parseReturn()
        case "guard":
            return try parseGuard()
        case "defer":
            return try parseDefer()
        case "break":
            return try parseBreak()
        case "continue":
            let line = current.line
            guard loopDepth > 0 else {
                throw syntaxError("'continue' só pode ser usado dentro de um laço")
            }
            advance()
            try consumeSymbol(";")
            return .continueFlow(line: line)
        case "fn", "recursive", "struct", "enum":
            throw syntaxError("Declarações de tipo e função ficam no nível superior")
        default:
            return try parseExpressionStatement()
        }
    }

    private mutating func parseDeclaration() throws -> GooseStatement {
        let line = current.line
        let mutable = currentKeyword == "var"
        advance()

        var names = [try consumeName()]
        while consumeSymbolIf(",") {
            names.append(try consumeName())
        }

        var typeName: String?
        if isSymbol(":") {
            typeName = try parseTypeName()
        }
        try consumeSymbol("=")
        let value = try parseExpression()
        try consumeSymbol(";")
        return .declare(names: names, mutable: mutable, typeName: typeName, value: value, line: line)
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

    private mutating func parseLoopForever() throws -> GooseStatement {
        let line = current.line
        try consumeKeyword("loop")

        loopDepth += 1
        let body = try parseBlock()
        loopDepth -= 1

        return .loopForever(body, line: line)
    }

    private mutating func parseForEach() throws -> GooseStatement {
        let line = current.line
        try consumeKeyword("for")

        // `for &x in xs` binds by reference: the writes go back to the array.
        let byReference = consumeSymbolIf("&")
        let name = try consumeName()
        try consumeKeyword("in")

        var iterable = try parseExpression()
        if consumeSymbolIf("..") {
            // `for i in a..b` stops before `b`.
            let upper = try parseExpression()
            iterable = .range(iterable, upper, line: line)
        }

        loopDepth += 1
        let body = try parseBlock()
        loopDepth -= 1

        return .forEach(
            name: name,
            byReference: byReference,
            iterable: iterable,
            body: body,
            line: line
        )
    }

    private mutating func parseReturn() throws -> GooseStatement {
        let line = current.line
        try consumeKeyword("return")
        if consumeSymbolIf(";") {
            return .returnValues([], line: line)
        }

        var values = [try parseExpression()]
        while consumeSymbolIf(",") {
            values.append(try parseExpression())
        }
        try consumeSymbol(";")
        return .returnValues(values, line: line)
    }

    private mutating func parseGuard() throws -> GooseStatement {
        let line = current.line
        try consumeKeyword("guard")
        let condition = try parseExpression()

        // `guard c;` runs the rest of the block only where `c` holds.
        if consumeSymbolIf(";") {
            return .guardCondition(condition, [], line: line)
        }

        try consumeKeyword("else")
        let body = try parseBlock()
        return .guardCondition(condition, body, line: line)
    }

    private mutating func parseDefer() throws -> GooseStatement {
        let line = current.line
        try consumeKeyword("defer")

        // `defer statement;` and `defer { … }` both work in Goose.
        if isSymbol("{") {
            return .deferBlock(try parseBlock(), line: line)
        }
        return .deferBlock([try parseStatement()], line: line)
    }

    private mutating func parseBreak() throws -> GooseStatement {
        let line = current.line
        guard loopDepth > 0 || blockDepth > 0 else {
            throw syntaxError("'break' só pode ser usado dentro de um laço ou de um block")
        }
        advance()

        // `break` alone leaves a loop; `break value` leaves a block with it.
        if consumeSymbolIf(";") {
            return .breakFlow(nil, line: line)
        }

        let value = try parseExpression()
        try consumeSymbol(";")
        return .breakFlow(value, line: line)
    }

    private mutating func parseExpressionStatement() throws -> GooseStatement {
        let expression = try parseExpression()

        if isSymbol(",") {
            // `a, b = f()` assigns several results at once.
            var targets = [expression]
            while consumeSymbolIf(",") {
                targets.append(try parseExpression())
            }
            guard let op = assignmentOperator else {
                throw syntaxError("Esperado '=' depois de vários alvos")
            }
            advance()
            let value = try parseExpression()
            try consumeSymbol(";")
            guard targets.allSatisfy(isAssignable) else {
                throw GooseInterpreterError.syntax(
                    line: expression.line,
                    message: "Não é possível atribuir a esta expressão"
                )
            }
            return .assign(targets: targets, op: op, value: value, line: expression.line)
        }

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
            return .assign(targets: [expression], op: op, value: value, line: expression.line)
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
            return .assign(targets: [expression], op: op, value: one, line: expression.line)
        }

        // A block, an `if` chain or a `match` stands on its own, and the
        // trailing expression of a block needs no semicolon; every other
        // expression statement ends with one, as in Goose.
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
        case .conditional, .block, .match:
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
        nesting += 1
        defer { nesting -= 1 }
        guard nesting <= Self.nestingLimit else {
            throw GooseInterpreterError.syntax(
                line: current.line,
                message: "Aninhamento profundo demais (limite \(Self.nestingLimit))"
            )
        }
        return try parseBinary(minimumPrecedence: 1)
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
        if isSymbol("^") {
            // `^k` counts from the end; only a slice uses the value.
            let line = current.line
            advance()
            return .fromEnd(try parseUnary(), line: line)
        }
        // `&x` and `&mut x` are references; the interpreter is dynamically
        // typed, so the marker is accepted and the value passes through.
        if isSymbol("&") {
            advance()
            return try parseUnary()
        }
        return try parsePostfix()
    }

    private mutating func parsePostfix() throws -> GooseExpression {
        var expression = try parsePrimary()

        while true {
            if isSymbol("[") {
                expression = try parseBracket(expression)
            } else if consumeSymbolIf(".") {
                let name = try consumeName()

                if let enumName = enumName(of: expression) {
                    // `Enum.Variant` is a value; a payload may follow.
                    let arguments = isSymbol("{") ? try parseLiteralArguments() : []
                    expression = .variantLiteral(enumName, name, arguments, line: expression.line)
                    continue
                }

                if consumeSymbolIf("(") {
                    expression = .method(expression, name, try parseArguments(), line: expression.line)
                } else {
                    expression = .field(expression, name, line: expression.line)
                }
            } else if consumeKeywordIf("as") {
                // The interpreter truncates like a release build; `as!` is
                // accepted as the same operation.
                _ = consumeSymbolIf("!")
                let typeName = try parseTypeName()
                expression = .cast(expression, typeName, checked: false, line: expression.line)
            } else {
                break
            }
        }

        return expression
    }

    /// Returns the enum name when `expression` is a bare enum type name.
    private func enumName(of expression: GooseExpression) -> String? {
        if case let .variable(name, _) = expression, enumNames.contains(name) {
            return name
        }
        return nil
    }

    /// Parses `[index]`, `[a..b]`, `[..b]`, `[a..]` and `[..]`.
    private mutating func parseBracket(_ base: GooseExpression) throws -> GooseExpression {
        let line = base.line
        advance()

        if consumeSymbolIf("..") {
            let upper = isSymbol("]") ? nil : try parseExpression()
            try consumeSymbol("]")
            return .slice(base, nil, upper, line: line)
        }

        let first = try parseExpression()
        if consumeSymbolIf("..") {
            let upper = isSymbol("]") ? nil : try parseExpression()
            try consumeSymbol("]")
            return .slice(base, first, upper, line: line)
        }

        try consumeSymbol("]")
        return .index(base, first, line: line)
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
            case "match":
                return try parseMatch()
            case "block":
                let line = token.line
                advance()
                blockDepth += 1
                let body = try parseBlock()
                blockDepth -= 1
                return .block(body, line: line)
            default:
                throw GooseInterpreterError.syntax(
                    line: token.line,
                    message: "Expressão inesperada: \(keyword)"
                )
            }

        case let .identifier(name):
            advance()
            if isSymbol("(") {
                advance()
                return .call(name, try parseArguments(), line: token.line)
            }
            if isSymbol("{"), structNames.contains(name) {
                return .structLiteral(name, try parseLiteralArguments(), line: token.line)
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

    /// Parses `{ 1, 2 }` or `{ x: 1, y: 2 }` after a type or variant name.
    /// A positional argument keeps a nil name; the declaration supplies it.
    private mutating func parseLiteralArguments() throws -> [GooseNamedArgument] {
        try consumeSymbol("{")
        var arguments: [GooseNamedArgument] = []

        while !isSymbol("}") {
            if case let .identifier(name) = current.kind, peekSymbol(ahead: 1, is: ":") {
                advance()
                advance()
                arguments.append(GooseNamedArgument(name: name, value: try parseExpression()))
            } else {
                arguments.append(GooseNamedArgument(name: nil, value: try parseExpression()))
            }
            _ = consumeSymbolIf(",")
        }

        try consumeSymbol("}")
        return arguments
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

    private mutating func parseMatch() throws -> GooseExpression {
        let line = current.line
        try consumeKeyword("match")
        let scrutinee = try parseExpression()
        try consumeSymbol("{")

        var arms: [GooseMatchArm] = []
        while !isSymbol("}") {
            arms.append(try parseMatchArm())
            _ = consumeSymbolIf(",")
        }

        try consumeSymbol("}")
        guard !arms.isEmpty else {
            throw GooseInterpreterError.syntax(line: line, message: "match sem nenhum braço")
        }
        return .match(scrutinee, arms, line: line)
    }

    private mutating func parseMatchArm() throws -> GooseMatchArm {
        // Patterns run until `=>`, so every comma seen here separates patterns.
        var patterns: [GoosePattern] = [try parsePattern()]
        while consumeSymbolIf(",") {
            patterns.append(try parsePattern())
        }

        try consumeSymbol("=>")
        let body = isSymbol("{") ? try parseBlock() : [.expression(try parseExpression())]
        return GooseMatchArm(patterns: patterns, body: body)
    }

    private mutating func parsePattern() throws -> GoosePattern {
        if case let .identifier(name) = current.kind {
            if name == "_" {
                advance()
                return .wildcard
            }
            advance()
            // `Rect r` binds the payload to `r`.
            if case let .identifier(binder) = current.kind {
                advance()
                return .variant(name, binder: binder)
            }
            return .variant(name, binder: nil)
        }

        if case let .integer(text) = current.kind {
            guard let lower = Int64(text) else {
                throw syntaxError("Número inválido no padrão: \(text)")
            }
            advance()
            if consumeSymbolIf("..") {
                guard case let .integer(upperText) = current.kind, let upper = Int64(upperText) else {
                    throw syntaxError("Esperado um inteiro após '..'")
                }
                advance()
                return .range(lower, upper)
            }
            return .integer(lower)
        }

        if case .symbol("-") = current.kind {
            advance()
            guard case let .integer(text) = current.kind, let value = Int64(text) else {
                throw syntaxError("Esperado um inteiro negativo no padrão")
            }
            advance()
            return .integer(-value)
        }

        throw syntaxError("Padrão esperado no match")
    }

    // MARK: - Blocks and types

    private mutating func parseBlock() throws -> [GooseStatement] {
        nesting += 1
        defer { nesting -= 1 }
        guard nesting <= Self.nestingLimit else {
            throw GooseInterpreterError.syntax(
                line: current.line,
                message: "Aninhamento profundo demais (limite \(Self.nestingLimit))"
            )
        }

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

    /// Reads a type annotation such as `u8`, `f64`, `i64[>..]`, `Shape` or
    /// `i64?`.
    private mutating func parseTypeName() throws -> String {
        if isSymbol(":") {
            advance()
        }
        var parts: [String] = []
        var depth = 0

        while !isAtEnd {
            if depth == 0,
               isSymbol("=") || isSymbol(";") || isSymbol(",") || isSymbol(")")
                || isSymbol("{") || isSymbol("}") {
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
            if depth == 0, isSymbol(",") || isSymbol(")") || isSymbol("{") || isSymbol("}") {
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

    private func peekSymbol(ahead offset: Int, is symbol: String) -> Bool {
        let position = index + offset
        guard position < tokens.count else { return false }
        return tokens[position].kind == .symbol(symbol)
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
