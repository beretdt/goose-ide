import Foundation

// MARK: - Values

/// An integer that knows its declared width, so that `u8 + u8` wraps at 8
/// bits and a literal adapts to the width of the value it meets.
struct GooseInteger: Equatable {
    var value: Int64
    var bits: Int
    var isSigned: Bool
    var isLiteral: Bool

    static func literal(_ value: Int64) -> GooseInteger {
        GooseInteger(value: value, bits: 64, isSigned: true, isLiteral: true)
    }

    /// Cuts the value down to its own width, two's complement for signed types.
    func normalized() -> GooseInteger {
        guard bits < 64 else {
            var result = self
            result.isLiteral = false
            return result
        }
        let mask = (UInt64(1) << UInt64(bits)) - 1
        var raw = UInt64(bitPattern: value) & mask
        if isSigned, (raw & (UInt64(1) << UInt64(bits - 1))) != 0 {
            raw |= ~mask
        }
        var result = self
        result.value = Int64(bitPattern: raw)
        result.isLiteral = false
        return result
    }

    var display: String {
        if isSigned || (bits == 64 && value >= 0) {
            return String(value)
        }
        return String(UInt64(bitPattern: value))
    }

    func asIntegerType(
        bits newBits: Int,
        signed: Bool,
        checked: Bool
    ) throws -> GooseInteger {
        let target = GooseInteger(
            value: value,
            bits: newBits,
            isSigned: signed,
            isLiteral: false
        ).normalized()
        if checked && target.value != value {
            throw GooseInterpreterError.runtime(
                line: 0,
                message: "valor \(value) não cabe em \(signed ? "i" : "u")\(newBits)"
            )
        }
        return target
    }
}

struct GooseArray {
    var elements: [GooseValue]
    /// `u8[...]` is text in Goose: it prints as characters, not numbers.
    var isByteArray: Bool

    init(_ elements: [GooseValue] = [], isByteArray: Bool = false) {
        self.elements = elements
        self.isByteArray = isByteArray
    }

    var asText: String? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(elements.count)
        for element in elements {
            guard case let .integer(integer) = element, (0...255).contains(integer.value) else {
                return nil
            }
            bytes.append(UInt8(integer.value))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    func copied() -> GooseArray {
        GooseArray(elements.map(\.copied), isByteArray: isByteArray)
    }
}

/// A struct value, or an enum value (`variant` is set for the latter).
struct GooseComposite {
    let typeName: String
    let variant: String?
    var fields: [(name: String, value: GooseValue)]

    func value(of field: String) -> GooseValue? {
        fields.first { $0.name == field }?.value
    }

    func copied() -> GooseComposite {
        GooseComposite(
            typeName: typeName,
            variant: variant,
            fields: fields.map { ($0.name, $0.value.copied) }
        )
    }

    /// A struct prints its type and every field; a variant with a payload
    /// prints its variant, and one without prints `Enum.Variant`.
    func render() -> String {
        let values = fields.map { $0.value.render(nested: true) }.joined(separator: ", ")
        guard let variant else {
            return "\(typeName) { \(values) }"
        }
        guard !fields.isEmpty else {
            return "\(typeName).\(variant)"
        }
        return "\(variant) { \(values) }"
    }
}

enum GooseValue {
    case integer(GooseInteger)
    case double(Double)
    case bool(Bool)
    case string(String)
    case array(GooseArray)
    case composite(GooseComposite)
    case null
    /// Only `return a, b` and a call of such a function produce one.
    case tuple([GooseValue])

    /// `nested` is true inside a container, where a byte array shows quotes.
    func render(nested: Bool = false) -> String {
        switch self {
        case let .integer(integer):
            return integer.display
        case let .double(double):
            // Swift renders 1.0 as "1.0" and 0.75 as "0.75", matching Goose.
            return String(double)
        case let .bool(value):
            return value ? "true" : "false"
        case let .string(value):
            return value
        case let .array(array):
            if array.isByteArray, let text = array.asText {
                return nested ? "\"\(text)\"" : text
            }
            return "[" + array.elements.map { $0.render(nested: true) }.joined(separator: ", ") + "]"
        case let .composite(composite):
            return composite.render()
        case let .tuple(values):
            return values.map { $0.render(nested: nested) }.joined()
        case .null:
            return "null"
        }
    }

    var rendered: String {
        render()
    }

    var copied: GooseValue {
        switch self {
        case let .array(array):
            return .array(array.copied())
        case let .composite(composite):
            return .composite(composite.copied())
        case let .tuple(values):
            return .tuple(values.map(\.copied))
        default:
            return self
        }
    }

    /// Unwraps a one-element tuple, which is what a single-result function
    /// hands back after `return value;`.
    var single: GooseValue {
        if case let .tuple(values) = self, values.count == 1 {
            return values[0]
        }
        return self
    }
}

// MARK: - Environment

final class GooseEnvironment {
    private var values: [String: GooseValue]
    private var mutables: Set<String>
    let parent: GooseEnvironment?

    init(parent: GooseEnvironment? = nil) {
        self.parent = parent
        values = [:]
        mutables = []
    }

    func declare(_ name: String, mutable: Bool, value: GooseValue) {
        values[name] = value
        if mutable {
            mutables.insert(name)
        } else {
            mutables.remove(name)
        }
    }

    func lookup(_ name: String) -> GooseValue? {
        if let value = values[name] { return value }
        return parent?.lookup(name)
    }

    func isMutable(_ name: String) -> Bool {
        if values[name] != nil { return mutables.contains(name) }
        return parent?.isMutable(name) ?? false
    }

    func assign(_ name: String, value: GooseValue, line: Int) throws {
        if values[name] != nil {
            guard mutables.contains(name) else {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "'\(name)' foi declarado com let; use var para alterá-lo"
                )
            }
            values[name] = value
            return
        }
        guard let parent else {
            throw GooseInterpreterError.runtime(line: line, message: "Variável não declarada: \(name)")
        }
        try parent.assign(name, value: value, line: line)
    }
}

// MARK: - Control flow

/// `return`, `break` and `continue` travel as errors so that they cross
/// expression boundaries (`if`, `match`, blocks) without being lost.
enum GooseControlFlow: Error {
    case returned([GooseValue])
    case breakLoop
    case continueLoop
    case breakBlock(GooseValue)
}

// MARK: - Runtime

final class GooseRuntime {
    private static let stepLimit = 2_000_000
    private static let callDepthLimit = 200
    private static let outputLimit = 500_000

    private let program: GooseProgram
    private let globals = GooseEnvironment()
    private var output = ""
    private var steps = 0
    private var callDepth = 0

    init(program: GooseProgram) {
        self.program = program
    }

    func run() throws -> String {
        do {
            if let main = program.functions["main"] {
                _ = try call(main, arguments: [], line: main.line)
            } else {
                _ = try execute(program.statements, in: globals)
            }
        } catch GooseControlFlow.returned {
            // A return at the top level ends the program.
        }
        return output
    }

    // MARK: Statements

    private func execute(
        _ statements: [GooseStatement],
        in environment: GooseEnvironment
    ) throws -> GooseValue {
        var deferred: [[GooseStatement]] = []

        do {
            var last: GooseValue = .null
            for statement in statements {
                try spendStep()
                if case let .deferBlock(body, _) = statement {
                    // Registered now, run in reverse when the block ends,
                    // which is what `defer` promises.
                    deferred.append(body)
                    continue
                }
                last = try execute(statement, in: environment)
            }
            try runDeferred(deferred, in: environment)
            return last
        } catch {
            try? runDeferred(deferred, in: environment)
            throw error
        }
    }

    private func runDeferred(
        _ blocks: [[GooseStatement]],
        in environment: GooseEnvironment
    ) throws {
        for body in blocks.reversed() {
            _ = try execute(body, in: GooseEnvironment(parent: environment))
        }
    }

    private func execute(
        _ statement: GooseStatement,
        in environment: GooseEnvironment
    ) throws -> GooseValue {
        switch statement {
        case let .declare(names, mutable, typeName, value, line):
            let evaluated = try evaluate(value, in: environment)
            try declare(names, from: evaluated, mutable: mutable, typeName: typeName, line: line, environment)
            return .null

        case let .assign(targets, op, value, line):
            let right = try evaluate(value, in: environment)
            try assign(targets, from: right, op: op, line: line, environment)
            return .null

        case let .expression(expression):
            return try evaluate(expression, in: environment).single

        case let .loopWhile(condition, body, _):
            while try isTrue(condition, in: environment) {
                try spendStep()
                do {
                    _ = try execute(body, in: GooseEnvironment(parent: environment))
                } catch GooseControlFlow.breakLoop {
                    break
                } catch GooseControlFlow.continueLoop {
                    continue
                }
            }
            return .null

        case let .loopForever(body, _):
            while true {
                try spendStep()
                do {
                    _ = try execute(body, in: GooseEnvironment(parent: environment))
                } catch GooseControlFlow.breakLoop {
                    break
                } catch GooseControlFlow.continueLoop {
                    continue
                }
            }
            return .null

        case let .forEach(name, byReference, iterable, body, line):
            return try executeForEach(
                name,
                byReference: byReference,
                iterable,
                body,
                line,
                environment
            )

        case let .returnValues(expressions, line):
            guard !expressions.isEmpty else {
                throw GooseControlFlow.returned([])
            }
            var values: [GooseValue] = []
            for expression in expressions {
                let value = try evaluate(expression, in: environment).single
                values.append(value)
            }
            if values.count > 1, let only = values.first, case let .tuple(inner) = only {
                values = inner
            }
            _ = line
            throw GooseControlFlow.returned(values)

        case let .guardCondition(condition, elseBody, line):
            guard try isTrue(condition, in: environment) else {
                // `guard c;` ends the rest of the block quietly; with an else,
                // that block has to leave, and saying so beats continuing.
                guard !elseBody.isEmpty else {
                    throw GooseControlFlow.breakBlock(.null)
                }
                _ = try execute(elseBody, in: GooseEnvironment(parent: environment))
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "o else de um guard precisa sair (return, break ou continue)"
                )
            }
            return .null

        case let .deferBlock(body, _):
            // Handled by `execute(_:in:)`, which keeps the list.
            _ = body
            return .null

        case let .breakFlow(expression, line):
            if let expression {
                let value = try evaluate(expression, in: environment).single
                throw GooseControlFlow.breakBlock(value)
            }
            _ = line
            throw GooseControlFlow.breakLoop

        case .continueFlow:
            throw GooseControlFlow.continueLoop
        }
    }

    /// Binds one value per name, spreading a tuple when there is more than one.
    private func declare(
        _ names: [String],
        from value: GooseValue,
        mutable: Bool,
        typeName: String?,
        line: Int,
        _ environment: GooseEnvironment
    ) throws {
        if names.count == 1 {
            let coerced = try typeName.map { try coerce(value.single, to: $0, line: line) } ?? value.single
            environment.declare(names[0], mutable: mutable, value: coerced.copied)
            return
        }

        guard case let .tuple(values) = value, values.count == names.count else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "\(names.count) nome(s) precisam de \(names.count) resultado(s), veio \(value.rendered)"
            )
        }
        for (name, item) in zip(names, values) {
            environment.declare(name, mutable: mutable, value: item.copied)
        }
    }

    private func assign(
        _ targets: [GooseExpression],
        from value: GooseValue,
        op: String,
        line: Int,
        _ environment: GooseEnvironment
    ) throws {
        if targets.count == 1 {
            let target = targets[0]
            let result = op == "="
                ? value.single
                : try applyBinary(
                    String(op.dropLast()),
                    try evaluate(target, in: environment).single,
                    value.single,
                    line: line
                )
            try assign(result, to: target, in: environment, line: line)
            return
        }

        guard op == "=" else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "atribuição composta só funciona com um alvo"
            )
        }
        guard case let .tuple(values) = value, values.count == targets.count else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "\(targets.count) alvo(s) precisam de \(targets.count) resultado(s)"
            )
        }
        for (target, item) in zip(targets, values) {
            try assign(item.copied, to: target, in: environment, line: line)
        }
    }

    private func executeForEach(
        _ name: String,
        byReference: Bool,
        _ iterable: GooseExpression,
        _ body: [GooseStatement],
        _ line: Int,
        _ environment: GooseEnvironment
    ) throws -> GooseValue {
        let sequence = try evaluate(iterable, in: environment)

        func iteration(_ value: GooseValue) throws -> Bool {
            try spendStep()
            let scope = GooseEnvironment(parent: environment)
            scope.declare(name, mutable: byReference, value: value.copied)
            do {
                _ = try execute(body, in: scope)
            } catch GooseControlFlow.breakLoop {
                return false
            } catch GooseControlFlow.continueLoop {
                return true
            }
            return true
        }

        switch sequence {
        case let .integer(integer):
            for step in 0..<max(0, Int(integer.value)) {
                guard try iteration(.integer(.literal(Int64(step)))) else { return .null }
            }
            return .null

        case var .array(array):
            if byReference {
                // `for &x in xs` writes the binding back, which is the
                // mutation form of the loop.
                guard try isMutableRoot(iterable, in: environment) else {
                    throw GooseInterpreterError.runtime(
                        line: line,
                        message: "for &x exige um array que possa ser alterado"
                    )
                }

                for offset in array.elements.indices {
                    let scope = GooseEnvironment(parent: environment)
                    scope.declare(name, mutable: true, value: array.elements[offset].copied)
                    var stopped = false
                    do {
                        _ = try execute(body, in: scope)
                    } catch GooseControlFlow.breakLoop {
                        stopped = true
                    } catch GooseControlFlow.continueLoop {
                        // A continue still keeps whatever the body wrote.
                    }
                    if let updated = scope.lookup(name) {
                        array.elements[offset] = updated
                    }
                    if stopped { break }
                }

                // The array is a value here, so the writes go back to it.
                try assign(.array(array), to: iterable, in: environment, line: line)
                return .null
            }

            for element in array.elements {
                guard try iteration(element) else { return .null }
            }
            return .null

        default:
            throw GooseInterpreterError.runtime(
                line: line,
                message: "for espera um inteiro, uma faixa ou um array, não \(sequence.rendered)"
            )
        }
    }

    private func assign(
        _ value: GooseValue,
        to target: GooseExpression,
        in environment: GooseEnvironment,
        line: Int
    ) throws {
        switch target {
        case let .variable(name, _):
            try environment.assign(name, value: value.copied, line: line)

        case let .index(base, indexExpression, _):
            guard try isMutableRoot(base, in: environment) else {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "Não é possível alterar um array declarado com let"
                )
            }
            guard case var .array(array) = try evaluate(base, in: environment) else {
                throw GooseInterpreterError.runtime(line: line, message: "Só arrays aceitam índice")
            }
            let position = try arrayIndex(
                indexExpression,
                in: environment,
                count: array.elements.count,
                line: line
            )
            array.elements[position] = value.copied
            try writeBack(.array(array), to: base, in: environment, line: line)

        case let .field(base, name, _):
            guard try isMutableRoot(base, in: environment) else {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "Não é possível alterar um valor declarado com let"
                )
            }
            guard case var .composite(composite) = try evaluate(base, in: environment) else {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "O campo '.\(name)' não existe neste valor"
                )
            }
            guard let position = composite.fields.firstIndex(where: { $0.name == name }) else {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "O campo '.\(name)' não existe em \(composite.typeName)"
                )
            }
            composite.fields[position].value = value.copied
            try writeBack(.composite(composite), to: base, in: environment, line: line)

        default:
            throw GooseInterpreterError.runtime(line: line, message: "Alvo de atribuição inválido")
        }
    }

    /// Arrays and structs are values here, so a change made through an index
    /// or a field has to be written back into whatever holds them.
    private func writeBack(
        _ value: GooseValue,
        to target: GooseExpression,
        in environment: GooseEnvironment,
        line: Int
    ) throws {
        try assign(value, to: target, in: environment, line: line)
    }

    private func isMutableRoot(
        _ expression: GooseExpression,
        in environment: GooseEnvironment
    ) throws -> Bool {
        switch expression {
        case let .variable(name, _):
            return environment.isMutable(name)
        case let .index(base, _, _):
            return try isMutableRoot(base, in: environment)
        case let .field(base, _, _):
            return try isMutableRoot(base, in: environment)
        default:
            return true
        }
    }

    // MARK: Expressions

    private func evaluate(
        _ expression: GooseExpression,
        in environment: GooseEnvironment
    ) throws -> GooseValue {
        switch expression {
        case let .integer(text, line):
            return try parseInteger(text, line: line)

        case let .double(value, _):
            return .double(value)

        case let .boolean(value, _):
            return .bool(value)

        case let .string(value, _):
            return .string(value)

        case .null:
            return .null

        case let .variable(name, line):
            guard let value = environment.lookup(name) else {
                throw GooseInterpreterError.runtime(line: line, message: "Variável não declarada: \(name)")
            }
            return value

        case let .unary(op, operand, line):
            return try applyUnary(op, try evaluate(operand, in: environment).single, line: line)

        case let .binary(op, left, right, line):
            if op == "&&" {
                return .bool(try isTrue(left, in: environment) && isTrue(right, in: environment))
            }
            if op == "||" {
                return .bool(try isTrue(left, in: environment) || isTrue(right, in: environment))
            }
            return try applyBinary(
                op,
                try evaluate(left, in: environment).single,
                try evaluate(right, in: environment).single,
                line: line
            )

        case let .call(name, arguments, line):
            return try call(named: name, arguments: arguments, in: environment, line: line)

        case let .method(receiver, name, arguments, line):
            return try callMethod(receiver, name: name, arguments: arguments, in: environment, line: line)

        case let .field(receiver, name, line):
            return try readField(receiver, name: name, in: environment, line: line)

        case let .index(base, indexExpression, line):
            let container = try evaluate(base, in: environment).single
            guard case let .array(array) = container else {
                throw GooseInterpreterError.runtime(line: line, message: "Só arrays aceitam índice")
            }
            let position = try arrayIndex(
                indexExpression,
                in: environment,
                count: array.elements.count,
                line: line
            )
            return array.elements[position]

        case let .arrayLiteral(elements, _):
            return .array(GooseArray(try elements.map { try evaluate($0, in: environment).single }))

        case let .arrayFill(value, count, line):
            let element = try evaluate(value, in: environment).single
            guard case let .integer(integer) = try evaluate(count, in: environment).single,
                  integer.value >= 0 else {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "A contagem da repetição deve ser um inteiro não negativo"
                )
            }
            return .array(GooseArray(Array(repeating: element, count: Int(integer.value))))

        case let .conditional(condition, thenBody, elseBody, _):
            if try isTrue(condition, in: environment) {
                return try execute(thenBody, in: GooseEnvironment(parent: environment))
            }
            guard let elseBody else { return .null }
            return try execute(elseBody, in: GooseEnvironment(parent: environment))

        case let .match(scrutinee, arms, line):
            return try evaluateMatch(scrutinee, arms, line, environment)

        case let .block(body, _):
            do {
                return try execute(body, in: GooseEnvironment(parent: environment))
            } catch let GooseControlFlow.breakBlock(value) {
                return value
            }

        case let .cast(value, typeName, checked, line):
            return try cast(try evaluate(value, in: environment).single, to: typeName, checked: checked, line: line)

        case let .structLiteral(typeName, arguments, line):
            return try buildStruct(typeName, arguments, line, environment)

        case let .variantLiteral(enumName, variant, arguments, line):
            return try buildVariant(enumName, variant, arguments, line, environment)

        case let .slice(base, lower, upper, line):
            return try slice(base, lower, upper, line, environment)

        case .fromEnd(_, let line):
            throw GooseInterpreterError.runtime(
                line: line,
                message: "'^' só pode ser usado dentro de um slice"
            )

        case let .range(from, to, line):
            let lower = try integerValue(from, in: environment, line: line)
            let upper = try integerValue(to, in: environment, line: line)
            let values = lower < upper ? Array(lower..<upper) : []
            return .array(GooseArray(values.map { .integer(.literal($0)) }))

        case let .tuple(expressions, _):
            return .tuple(try expressions.map { try evaluate($0, in: environment).single })
        }
    }

    private func isTrue(_ expression: GooseExpression, in environment: GooseEnvironment) throws -> Bool {
        let value = try evaluate(expression, in: environment).single
        guard case let .bool(flag) = value else {
            throw GooseInterpreterError.runtime(
                line: expression.line,
                message: "Esperado bool, não \(value.rendered)"
            )
        }
        return flag
    }

    private func integerValue(
        _ expression: GooseExpression,
        in environment: GooseEnvironment,
        line: Int
    ) throws -> Int64 {
        guard case let .integer(integer) = try evaluate(expression, in: environment).single else {
            throw GooseInterpreterError.runtime(line: line, message: "Esperado um inteiro")
        }
        return integer.value
    }

    private func arrayIndex(
        _ expression: GooseExpression,
        in environment: GooseEnvironment,
        count: Int,
        line: Int
    ) throws -> Int {
        let position = Int(try integerValue(expression, in: environment, line: line))
        guard position >= 0, position < count else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "Índice \(position) fora de um array de \(count) elementos"
            )
        }
        return position
    }

    // MARK: Composites

    private func buildStruct(
        _ typeName: String,
        _ arguments: [GooseNamedArgument],
        _ line: Int,
        _ environment: GooseEnvironment
    ) throws -> GooseValue {
        guard let declaration = program.structs[typeName] else {
            throw GooseInterpreterError.runtime(line: line, message: "struct desconhecida: \(typeName)")
        }
        let fields = try fillFields(
            declaration.fields,
            arguments,
            owner: typeName,
            line: line,
            environment
        )
        return .composite(GooseComposite(typeName: typeName, variant: nil, fields: fields))
    }

    private func buildVariant(
        _ enumName: String,
        _ variantName: String,
        _ arguments: [GooseNamedArgument],
        _ line: Int,
        _ environment: GooseEnvironment
    ) throws -> GooseValue {
        guard let declaration = program.enums[enumName] else {
            throw GooseInterpreterError.runtime(line: line, message: "enum desconhecida: \(enumName)")
        }
        guard let variant = declaration.variants.first(where: { $0.name == variantName }) else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "\(enumName) não tem a variante \(variantName)"
            )
        }
        let fields = try fillFields(variant.fields, arguments, owner: variantName, line: line, environment)
        return .composite(GooseComposite(typeName: enumName, variant: variantName, fields: fields))
    }

    private func fillFields(
        _ declaration: [GooseFieldDecl],
        _ arguments: [GooseNamedArgument],
        owner: String,
        line: Int,
        _ environment: GooseEnvironment
    ) throws -> [(name: String, value: GooseValue)] {
        var given: [String: GooseValue] = [:]
        var positional: [GooseValue] = []

        for argument in arguments {
            let value = try evaluate(argument.value, in: environment).single
            if let name = argument.name {
                given[name] = value
            } else {
                positional.append(value)
            }
        }

        guard positional.count <= declaration.count else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "\(owner) tem \(declaration.count) campo(s); recebeu \(positional.count)"
            )
        }

        var fields: [(name: String, value: GooseValue)] = []
        for (position, field) in declaration.enumerated() {
            let value: GooseValue
            if let named = given.removeValue(forKey: field.name) {
                value = named
            } else if let defaultValue = field.defaultValue {
                value = try evaluate(defaultValue, in: globals).single
            } else if position < positional.count {
                value = positional[position]
            } else {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "\(owner) precisa do campo '\(field.name)'"
                )
            }

            fields.append((field.name, try coerce(value, to: field.typeName, line: line)))
        }

        guard given.isEmpty else {
            let extra = given.keys.sorted().joined(separator: ", ")
            throw GooseInterpreterError.runtime(
                line: line,
                message: "\(owner) não tem o campo: \(extra)"
            )
        }
        return fields
    }

    // MARK: Match

    private enum MatchOutcome {
        case noMatch
        case matched(binder: (name: String, value: GooseValue)?)
    }

    private func evaluateMatch(
        _ scrutinee: GooseExpression,
        _ arms: [GooseMatchArm],
        _ line: Int,
        _ environment: GooseEnvironment
    ) throws -> GooseValue {
        let subject = try evaluate(scrutinee, in: environment).single

        for arm in arms {
            for pattern in arm.patterns {
                guard case let .matched(binder) = try match(pattern, against: subject, environment, line: line) else {
                    continue
                }
                let scope = GooseEnvironment(parent: environment)
                if let binder {
                    scope.declare(binder.name, mutable: true, value: binder.value)
                }
                return try execute(arm.body, in: scope)
            }
        }

        throw GooseInterpreterError.runtime(
            line: line,
            message: "match sem braço para \(subject.rendered)"
        )
    }

    private func match(
        _ pattern: GoosePattern,
        against subject: GooseValue,
        _ environment: GooseEnvironment,
        line: Int
    ) throws -> MatchOutcome {
        switch pattern {
        case .wildcard:
            return .matched(binder: nil)

        case let .name(name):
            guard case let .integer(named)? = environment.lookup(name),
                  case let .integer(integer) = subject,
                  named.value == integer.value else {
                return .noMatch
            }
            return .matched(binder: nil)

        case let .variant(name, binder):
            switch subject {
            case let .composite(composite):
                guard composite.variant == name else { return .noMatch }
                guard let binder else { return .matched(binder: nil) }
                let payload = GooseComposite(typeName: name, variant: nil, fields: composite.fields)
                return .matched(binder: (binder, .composite(payload)))
            case let .integer(integer):
                // A bare name may be a constant; `let` globals work here.
                guard case let .integer(named)? = environment.lookup(name) else { return .noMatch }
                return named.value == integer.value ? .matched(binder: nil) : .noMatch
            default:
                return .noMatch
            }

        case let .integer(expected):
            guard case let .integer(integer) = subject, integer.value == expected else { return .noMatch }
            return .matched(binder: nil)

        case let .range(lower, upper):
            guard case let .integer(integer) = subject else { return .noMatch }
            guard integer.value >= lower, integer.value < upper else { return .noMatch }
            return .matched(binder: nil)
        }
    }

    private func slice(
        _ base: GooseExpression,
        _ lower: GooseExpression?,
        _ upper: GooseExpression?,
        _ line: Int,
        _ environment: GooseEnvironment
    ) throws -> GooseValue {
        let container = try evaluate(base, in: environment).single
        guard case let .array(array) = container else {
            throw GooseInterpreterError.runtime(line: line, message: "Só arrays aceitam slice")
        }

        let count = Int64(array.elements.count)
        let start = try bound(lower, count: count, fallback: 0, environment, line: line)
        let end = try bound(upper, count: count, fallback: count, environment, line: line)

        guard start >= 0, end >= start, end <= count else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "Slice \(start)..\(end) fora de um array de \(count) elementos"
            )
        }

        return .array(
            GooseArray(Array(array.elements[Int(start)..<Int(end)]), isByteArray: array.isByteArray)
        )
    }

    private func bound(
        _ expression: GooseExpression?,
        count: Int64,
        fallback: Int64,
        _ environment: GooseEnvironment,
        line: Int
    ) throws -> Int64 {
        guard let expression else { return fallback }
        if case let .fromEnd(inner, _) = expression {
            let offset = try integerValue(inner, in: environment, line: line)
            return count - offset
        }
        return try integerValue(expression, in: environment, line: line)
    }

    // MARK: Calls

    private func call(
        named name: String,
        arguments: [GooseExpression],
        in environment: GooseEnvironment,
        line: Int
    ) throws -> GooseValue {
        switch name {
        case "print":
            let text = try arguments.map { try evaluate($0, in: environment).single.rendered }
            try append(text.joined() + "\n")
            return .null

        case "str":
            let text = try arguments.map { try evaluate($0, in: environment).single.rendered }
            return .string(text.joined())

        case "format":
            return try format(arguments, in: environment, line: line)

        default:
            guard let function = program.functions[name] else {
                throw GooseInterpreterError.runtime(line: line, message: "Função desconhecida: \(name)")
            }
            let values = try arguments.map { try evaluate($0, in: environment).single }
            return try call(function, arguments: values, line: line)
        }
    }

    /// `format(dest, …)` appends the rendered arguments to a `u8[…]` array.
    private func format(
        _ arguments: [GooseExpression],
        in environment: GooseEnvironment,
        line: Int
    ) throws -> GooseValue {
        guard let destination = arguments.first else {
            throw GooseInterpreterError.runtime(line: line, message: "format espera um destino")
        }

        let text = try arguments.dropFirst().map {
            try evaluate($0, in: environment).single.rendered
        }.joined()

        let target: GooseExpression
        if case let .variable(name, _) = destination {
            target = .variable(name, line: line)
        } else {
            target = destination
        }

        guard case var .array(array) = try evaluate(target, in: environment).single else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "format precisa de um array como destino"
            )
        }
        array.isByteArray = true
        array.elements.append(contentsOf: text.utf8.map { .integer(.literal(Int64($0))) })
        try assign(.array(array), to: target, in: environment, line: line)
        return .null
    }

    private func call(_ function: GooseFunction, arguments: [GooseValue], line: Int) throws -> GooseValue {
        guard callDepth < Self.callDepthLimit else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "Recursão profunda demais em '\(function.name)'"
            )
        }
        guard arguments.count == function.parameters.count else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "'\(function.name)' espera \(function.parameters.count) argumento(s), recebeu \(arguments.count)"
            )
        }

        let scope = GooseEnvironment(parent: globals)
        for (name, value) in zip(function.parameters, arguments) {
            scope.declare(name, mutable: true, value: value.copied)
        }

        callDepth += 1
        defer { callDepth -= 1 }

        do {
            return try execute(function.body, in: scope)
        } catch let GooseControlFlow.returned(values) {
            return values.count == 1 ? values[0] : .tuple(values)
        } catch GooseControlFlow.breakBlock {
            // `guard c;` in a function body skips the rest of it, and a
            // function with no result hands back nothing.
            return .null
        }
    }

    private func callMethod(
        _ receiver: GooseExpression,
        name: String,
        arguments: [GooseExpression],
        in environment: GooseEnvironment,
        line: Int
    ) throws -> GooseValue {
        let target = try evaluate(receiver, in: environment).single

        switch name {
        case "push":
            let (array, root) = try mutableArray(target, receiver, name: name, environment, line: line)
            guard let first = arguments.first else {
                throw GooseInterpreterError.runtime(line: line, message: "push espera um valor")
            }
            var updated = array
            updated.elements.append(try evaluate(first, in: environment).single.copied)
            try assign(.array(updated), to: root, in: environment, line: line)
            return .null

        case "pop":
            let (array, root) = try mutableArray(target, receiver, name: name, environment, line: line)
            var updated = array
            guard let last = updated.elements.popLast() else {
                throw GooseInterpreterError.runtime(line: line, message: "pop em um array vazio")
            }
            try assign(.array(updated), to: root, in: environment, line: line)
            return last

        case "append":
            let (array, root) = try mutableArray(target, receiver, name: name, environment, line: line)
            var updated = array
            for argument in arguments {
                let value = try evaluate(argument, in: environment).single
                switch value {
                case let .array(other):
                    updated.elements.append(contentsOf: other.elements.map(\.copied))
                case let .string(text):
                    updated.elements.append(contentsOf: text.utf8.map { .integer(.literal(Int64($0))) })
                default:
                    updated.elements.append(value)
                }
            }
            try assign(.array(updated), to: root, in: environment, line: line)
            return .null

        default:
            throw GooseInterpreterError.runtime(line: line, message: "Método desconhecido: .\(name)")
        }
    }

    /// Gives back the array and the expression its changes must be written to.
    private func mutableArray(
        _ target: GooseValue,
        _ receiver: GooseExpression,
        name: String,
        _ environment: GooseEnvironment,
        line: Int
    ) throws -> (GooseArray, GooseExpression) {
        guard case let .array(array) = target else {
            throw GooseInterpreterError.runtime(line: line, message: "\(name) existe apenas em arrays")
        }
        guard try isMutableRoot(receiver, in: environment) else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "Não é possível alterar um array declarado com let"
            )
        }
        return (array, receiver)
    }

    private func readField(
        _ receiver: GooseExpression,
        name: String,
        in environment: GooseEnvironment,
        line: Int
    ) throws -> GooseValue {
        let target = try evaluate(receiver, in: environment).single

        switch (name, target) {
        case ("len", .array(let array)):
            return .integer(.literal(Int64(array.elements.count)))
        case ("len", .string(let text)):
            return .integer(.literal(Int64(text.utf8.count)))
        case ("cap", .array(let array)):
            return .integer(.literal(Int64(array.elements.count)))
        default:
            if case let .composite(composite) = target {
                guard let value = composite.value(of: name) else {
                    throw GooseInterpreterError.runtime(
                        line: line,
                        message: "\(composite.typeName) não tem o campo '\(name)'"
                    )
                }
                return value
            }
            throw GooseInterpreterError.runtime(line: line, message: "Campo desconhecido: .\(name)")
        }
    }

    // MARK: Operators

    private func applyUnary(_ op: String, _ value: GooseValue, line: Int) throws -> GooseValue {
        switch (op, value) {
        case ("-", let .integer(integer)):
            var negated = integer
            negated.value = 0 &- integer.value
            return .integer(negated.normalized())
        case ("-", let .double(double)):
            return .double(-double)
        case ("+", let value):
            return value
        case ("!", let .bool(flag)):
            return .bool(!flag)
        default:
            throw GooseInterpreterError.runtime(
                line: line,
                message: "Operador '\(op)' inválido para \(value.rendered)"
            )
        }
    }

    private func applyBinary(
        _ op: String,
        _ left: GooseValue,
        _ right: GooseValue,
        line: Int
    ) throws -> GooseValue {
        switch (left, right) {
        case let (.integer(a), .integer(b)):
            return try integerOperation(op, a, b, line: line)
        case let (.double(a), .double(b)):
            return try doubleOperation(op, a, b, line: line)
        case let (.integer(a), .double(b)):
            return try doubleOperation(op, Double(a.value), b, line: line)
        case let (.double(a), .integer(b)):
            return try doubleOperation(op, a, Double(b.value), line: line)
        case let (.string(a), .string(b)):
            return try stringOperation(op, a, b, line: line)
        case let (.bool(a), .bool(b)):
            return try booleanOperation(op, a, b, line: line)
        case let (.composite(a), .composite(b)):
            return try compositeOperation(op, a, b, line: line)
        case (.null, .null) where op == "==":
            return .bool(true)
        case (_, .null) where op == "==", (.null, _) where op == "==":
            return .bool(false)
        case (_, .null) where op == "!=", (.null, _) where op == "!=":
            return .bool(true)
        default:
            throw GooseInterpreterError.runtime(
                line: line,
                message: "Operador '\(op)' inválido entre \(left.rendered) e \(right.rendered)"
            )
        }
    }

    private func integerOperation(
        _ op: String,
        _ a: GooseInteger,
        _ b: GooseInteger,
        line: Int
    ) throws -> GooseValue {
        // A literal takes the width of the value it meets, so `u8 + 42` is an
        // 8-bit add that wraps, as in Goose.
        let bits: Int
        let signed: Bool
        if a.isLiteral, !b.isLiteral {
            (bits, signed) = (b.bits, b.isSigned)
        } else if b.isLiteral, !a.isLiteral {
            (bits, signed) = (a.bits, a.isSigned)
        } else {
            bits = max(a.bits, b.bits)
            signed = a.bits == bits ? a.isSigned : b.isSigned
        }

        if a.bits == b.bits, a.isSigned != b.isSigned, !a.isLiteral, !b.isLiteral,
           op != "==", op != "!=" {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "Tipos com sinal e sem sinal do mesmo tamanho não se misturam; converta com 'as'"
            )
        }

        func result(_ value: Int64) -> GooseValue {
            .integer(
                GooseInteger(value: value, bits: bits, isSigned: signed, isLiteral: false).normalized()
            )
        }

        switch op {
        case "+": return result(a.value &+ b.value)
        case "-": return result(a.value &- b.value)
        case "*": return result(a.value &* b.value)
        case "/":
            guard b.value != 0 else {
                throw GooseInterpreterError.runtime(line: line, message: "Divisão por zero")
            }
            return result(a.value / b.value)
        case "%":
            guard b.value != 0 else {
                throw GooseInterpreterError.runtime(line: line, message: "Resto por zero")
            }
            let remainder = a.value % b.value
            return result(remainder < 0 ? remainder + abs(b.value) : remainder)
        case "==": return .bool(a.value == b.value)
        case "!=": return .bool(a.value != b.value)
        case "<": return .bool(a.value < b.value)
        case "<=": return .bool(a.value <= b.value)
        case ">": return .bool(a.value > b.value)
        case ">=": return .bool(a.value >= b.value)
        default:
            throw GooseInterpreterError.runtime(line: line, message: "Operador desconhecido: \(op)")
        }
    }

    private func doubleOperation(
        _ op: String,
        _ a: Double,
        _ b: Double,
        line: Int
    ) throws -> GooseValue {
        switch op {
        case "+": return .double(a + b)
        case "-": return .double(a - b)
        case "*": return .double(a * b)
        case "/":
            guard b != 0 else {
                throw GooseInterpreterError.runtime(line: line, message: "Divisão por zero")
            }
            return .double(a / b)
        case "%":
            guard b != 0 else {
                throw GooseInterpreterError.runtime(line: line, message: "Resto por zero")
            }
            let remainder = a.truncatingRemainder(dividingBy: b)
            return .double(remainder < 0 ? remainder + abs(b) : remainder)
        case "==": return .bool(a == b)
        case "!=": return .bool(a != b)
        case "<": return .bool(a < b)
        case "<=": return .bool(a <= b)
        case ">": return .bool(a > b)
        case ">=": return .bool(a >= b)
        default:
            throw GooseInterpreterError.runtime(line: line, message: "Operador desconhecido: \(op)")
        }
    }

    private func stringOperation(
        _ op: String,
        _ a: String,
        _ b: String,
        line: Int
    ) throws -> GooseValue {
        switch op {
        case "==": return .bool(a == b)
        case "!=": return .bool(a != b)
        case "<": return .bool(a < b)
        case "<=": return .bool(a <= b)
        case ">": return .bool(a > b)
        case ">=": return .bool(a >= b)
        default:
            throw GooseInterpreterError.runtime(
                line: line,
                message: "Goose não junta textos com '\(op)'; use print(...) ou str(...)"
            )
        }
    }

    private func booleanOperation(
        _ op: String,
        _ a: Bool,
        _ b: Bool,
        line: Int
    ) throws -> GooseValue {
        switch op {
        case "==": return .bool(a == b)
        case "!=": return .bool(a != b)
        default:
            throw GooseInterpreterError.runtime(line: line, message: "Operador desconhecido: \(op)")
        }
    }

    /// Structs of the same type add, subtract, multiply and divide field by
    /// field, which is how Goose moves a point.
    private func compositeOperation(
        _ op: String,
        _ a: GooseComposite,
        _ b: GooseComposite,
        line: Int
    ) throws -> GooseValue {
        guard a.typeName == b.typeName, a.variant == b.variant, a.fields.count == b.fields.count else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "Operador '\(op)' inválido entre \(a.render()) e \(b.render())"
            )
        }

        var fields: [(name: String, value: GooseValue)] = []
        for (left, right) in zip(a.fields, b.fields) {
            guard left.name == right.name else {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "Operador '\(op)' inválido entre \(a.render()) e \(b.render())"
                )
            }
            fields.append((left.name, try applyBinary(op, left.value, right.value, line: line)))
        }
        return .composite(GooseComposite(typeName: a.typeName, variant: a.variant, fields: fields))
    }

    // MARK: Types

    private func parseInteger(_ text: String, line: Int) throws -> GooseValue {
        guard let value = Int64(text) else {
            throw GooseInterpreterError.runtime(line: line, message: "Número inteiro inválido: \(text)")
        }
        return .integer(.literal(value))
    }

    private func coerce(_ value: GooseValue, to typeName: String?, line: Int) throws -> GooseValue {
        guard let typeName else { return value }

        // An optional is a nullable reference; the value itself is unchanged.
        let base = typeName.hasSuffix("?") ? String(typeName.dropLast()) : typeName

        if base.contains("[") || base.hasSuffix("..") {
            return try coerceToArrayType(value, typeName: base, line: line)
        }
        guard let normalized = Self.integerTypes[base] else {
            switch base {
            case "f32", "f64":
                guard case let .integer(integer) = value else { return value }
                return .double(Double(integer.value))
            default:
                return value
            }
        }
        guard case let .integer(integer) = value else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "Esperado \(base), não \(value.rendered)"
            )
        }
        return .integer(
            GooseInteger(
                value: integer.value,
                bits: normalized.bits,
                isSigned: normalized.signed,
                isLiteral: false
            ).normalized()
        )
    }

    private func coerceToArrayType(
        _ value: GooseValue,
        typeName: String,
        line: Int
    ) throws -> GooseValue {
        let isByteArray = typeName.hasPrefix("u8[") && typeName.filter({ $0 == "[" }).count == 1

        switch value {
        case var .array(array):
            if isByteArray {
                array.isByteArray = true
            }
            return .array(array)
        case let .string(text) where isByteArray:
            // A string literal fits a `u8[…]` field or variable.
            return .array(
                GooseArray(text.utf8.map { .integer(.literal(Int64($0))) }, isByteArray: true)
            )
        default:
            return value
        }
    }

    private func cast(
        _ value: GooseValue,
        to typeName: String,
        checked: Bool,
        line: Int
    ) throws -> GooseValue {
        if typeName == "f32" || typeName == "f64" {
            guard case let .integer(integer) = value else {
                throw GooseInterpreterError.runtime(line: line, message: "Conversão inválida para \(typeName)")
            }
            return .double(Double(integer.value))
        }
        guard let target = Self.integerTypes[typeName] else {
            throw GooseInterpreterError.runtime(line: line, message: "Tipo desconhecido: \(typeName)")
        }
        guard case let .integer(integer) = value else {
            throw GooseInterpreterError.runtime(line: line, message: "Conversão inválida para \(typeName)")
        }
        do {
            let narrowed = try integer.asIntegerType(
                bits: target.bits,
                signed: target.signed,
                checked: checked
            )
            return .integer(narrowed)
        } catch {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "valor \(integer.display) não cabe em \(typeName)"
            )
        }
    }

    private static let integerTypes: [String: (bits: Int, signed: Bool)] = [
        "i8": (8, true), "i16": (16, true), "i32": (32, true), "i64": (64, true),
        "u8": (8, false), "u16": (16, false), "u32": (32, false), "u64": (64, false),
    ]

    // MARK: Limits

    private func spendStep() throws {
        steps += 1
        guard steps <= Self.stepLimit else {
            throw GooseInterpreterError.runtime(
                line: 0,
                message: "O programa passou de \(Self.stepLimit) passos; verifique um laço infinito"
            )
        }
    }

    private func append(_ text: String) throws {
        guard output.count + text.count <= Self.outputLimit else {
            throw GooseInterpreterError.runtime(
                line: 0,
                message: "A saída passou de \(Self.outputLimit) caracteres"
            )
        }
        output += text
    }
}
