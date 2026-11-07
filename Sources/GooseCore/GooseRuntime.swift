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
        guard bits < 64 else { return self }
        let mask = (UInt64(1) << UInt64(bits)) - 1
        var raw = UInt64(bitPattern: value) & mask
        if isSigned, raw & (UInt64(1) << UInt64(bits - 1)) != 0 {
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

    func converted(bits newBits: Int, signed: Bool) -> GooseInteger {
        GooseInteger(value: value, bits: newBits, isSigned: signed, isLiteral: false).normalized()
    }
}

final class GooseArray {
    var elements: [GooseValue]
    /// A `u8` array is text in Goose: it prints as characters, not numbers.
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
}

enum GooseValue {
    case integer(GooseInteger)
    case double(Double)
    case bool(Bool)
    case string(String)
    case array(GooseArray)
    case null

    var rendered: String {
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
                return text
            }
            return "[" + array.elements.map(\.rendered).joined(separator: ", ") + "]"
        case .null:
            return "null"
        }
    }
}

// MARK: - Environment

final class GooseEnvironment {
    private var values: [String: GooseValue] = [:]
    private var mutables: Set<String> = []
    let parent: GooseEnvironment?

    init(parent: GooseEnvironment? = nil) {
        self.parent = parent
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
        values[name] ?? parent?.lookup(name)
    }

    func isMutable(_ name: String) -> Bool {
        values[name] != nil ? mutables.contains(name) : (parent?.isMutable(name) ?? false)
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

/// Control flow travels as thrown values so that a `return` inside an `if`
/// or a `break` inside a nested block reaches its target.
private struct GooseReturn: Error {
    let value: GooseValue
}

private struct GooseBreak: Error {}

private struct GooseContinue: Error {}

// MARK: - Runtime

final class GooseRuntime {
    private static let stepLimit = 2_000_000
    private static let callDepthLimit = 200
    private static let outputLimit = 500_000

    private static let integerTypes: [String: (bits: Int, signed: Bool)] = [
        "i8": (8, true), "i16": (16, true), "i32": (32, true), "i64": (64, true),
        "u8": (8, false), "u16": (16, false), "u32": (32, false), "u64": (64, false),
    ]

    private let program: GooseProgram
    private let globals = GooseEnvironment()
    private var output = ""
    private var steps = 0
    private var callDepth = 0

    init(program: GooseProgram) {
        self.program = program
    }

    func run() throws -> String {
        if let main = program.functions["main"] {
            _ = try call(main, arguments: [], line: main.line)
        } else {
            _ = try executeBlock(program.statements, in: globals)
        }
        return output
    }

    // MARK: Statements

    /// Executes a block; its value is the value of a trailing expression.
    private func executeBlock(_ statements: [GooseStatement], in environment: GooseEnvironment) throws -> GooseValue {
        var last: GooseValue = .null
        for statement in statements {
            try spendStep()
            last = try execute(statement, in: environment)
        }
        return last
    }

    private func execute(_ statement: GooseStatement, in environment: GooseEnvironment) throws -> GooseValue {
        switch statement {
        case let .declare(name, mutable, typeName, value, line):
            var evaluated = try evaluate(value, in: environment)
            if let typeName {
                evaluated = try coerce(evaluated, to: typeName, line: line)
            }
            environment.declare(name, mutable: mutable, value: evaluated)
            return .null

        case let .assign(target, op, value, line):
            let right = try evaluate(value, in: environment)
            let updated = op == "="
                ? right
                : try applyBinary(String(op.dropLast()), try evaluate(target, in: environment), right, line: line)
            try assign(updated, to: target, in: environment, line: line)
            return .null

        case let .expression(expression):
            return try evaluate(expression, in: environment)

        case let .loopWhile(condition, body, _):
            while try isTrue(condition, in: environment) {
                try spendStep()
                do {
                    _ = try executeBlock(body, in: GooseEnvironment(parent: environment))
                } catch is GooseBreak {
                    break
                } catch is GooseContinue {
                    continue
                }
            }
            return .null

        case let .forEach(name, iterable, body, line):
            return try executeForEach(name, iterable, body, line, environment)

        case let .returnValue(expression, _):
            throw GooseReturn(value: try expression.map { try evaluate($0, in: environment) } ?? .null)

        case .breakLoop:
            throw GooseBreak()

        case .continueLoop:
            throw GooseContinue()
        }
    }

    private func executeForEach(
        _ name: String,
        _ iterable: GooseExpression,
        _ body: [GooseStatement],
        _ line: Int,
        _ environment: GooseEnvironment
    ) throws -> GooseValue {
        let sequence = try evaluate(iterable, in: environment)

        func iteration(_ value: GooseValue) throws -> Bool {
            try spendStep()
            let scope = GooseEnvironment(parent: environment)
            scope.declare(name, mutable: false, value: value)
            do {
                _ = try executeBlock(body, in: scope)
                return false
            } catch is GooseBreak {
                return true
            } catch is GooseContinue {
                return false
            }
        }

        switch sequence {
        case let .integer(integer):
            for step in 0..<max(0, Int(integer.value)) {
                if try iteration(.integer(.literal(Int64(step)))) { break }
            }
            return .null

        case let .array(array):
            for element in array.elements {
                if try iteration(element) { break }
            }
            return .null

        default:
            throw GooseInterpreterError.runtime(
                line: line,
                message: "for espera um inteiro ou um array, não \(sequence.rendered)"
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
            try environment.assign(name, value: value, line: line)

        case let .index(base, indexExpression, _):
            guard try isMutableRoot(base, in: environment) else {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "Não é possível alterar um array declarado com let"
                )
            }
            guard case let .array(array) = try evaluate(base, in: environment) else {
                throw GooseInterpreterError.runtime(line: line, message: "Só arrays aceitam índice")
            }
            let position = try arrayIndex(indexExpression, in: environment, count: array.elements.count, line: line)
            array.elements[position] = value

        case let .field(_, name, _):
            throw GooseInterpreterError.runtime(line: line, message: "O campo '.\(name)' não pode ser alterado")

        default:
            throw GooseInterpreterError.runtime(line: line, message: "Alvo de atribuição inválido")
        }
    }

    private func isMutableRoot(_ expression: GooseExpression, in environment: GooseEnvironment) throws -> Bool {
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

    private func evaluate(_ expression: GooseExpression, in environment: GooseEnvironment) throws -> GooseValue {
        switch expression {
        case let .integer(text, line):
            guard let value = Int64(text) else {
                throw GooseInterpreterError.runtime(line: line, message: "Inteiro fora do intervalo de 64 bits: \(text)")
            }
            return .integer(.literal(value))

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
            return try evaluateUnary(op, try evaluate(operand, in: environment), line: line)

        case let .binary(operatorName, left, right, line):
            return try evaluateBinary(operatorName, left, right, line: line, environment: environment)

        case let .call(name, arguments, line):
            return try call(named: name, arguments: arguments, in: environment, line: line)

        case let .method(receiver, name, arguments, line):
            return try callMethod(receiver, name: name, arguments: arguments, in: environment, line: line)

        case let .field(receiver, name, line):
            return try readField(receiver, name: name, in: environment, line: line)

        case let .index(base, indexExpression, line):
            guard case let .array(array) = try evaluate(base, in: environment) else {
                throw GooseInterpreterError.runtime(line: line, message: "Só arrays aceitam índice")
            }
            let position = try arrayIndex(indexExpression, in: environment, count: array.elements.count, line: line)
            return array.elements[position]

        case let .arrayLiteral(elements, _):
            return .array(GooseArray(try elements.map { try evaluate($0, in: environment) }))

        case let .arrayFill(value, count, line):
            let element = try evaluate(value, in: environment)
            guard case let .integer(integer) = try evaluate(count, in: environment), integer.value >= 0 else {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "A contagem da repetição deve ser um inteiro não negativo"
                )
            }
            return .array(GooseArray(Array(repeating: element, count: Int(integer.value))))

        case let .conditional(condition, thenBody, elseBody, _):
            if try isTrue(condition, in: environment) {
                return try executeBlock(thenBody, in: GooseEnvironment(parent: environment))
            }
            guard let elseBody else { return .null }
            return try executeBlock(elseBody, in: GooseEnvironment(parent: environment))

        case let .block(body, _):
            return try executeBlock(body, in: GooseEnvironment(parent: environment))

        case let .cast(value, typeName, _, line):
            return try cast(try evaluate(value, in: environment), to: typeName, line: line)
        }
    }

    private func isTrue(_ expression: GooseExpression, in environment: GooseEnvironment) throws -> Bool {
        let value = try evaluate(expression, in: environment)
        guard case let .bool(flag) = value else {
            throw GooseInterpreterError.runtime(
                line: expression.line,
                message: "A condição deve ser bool, não \(value.rendered)"
            )
        }
        return flag
    }

    private func arrayIndex(
        _ expression: GooseExpression,
        in environment: GooseEnvironment,
        count: Int,
        line: Int
    ) throws -> Int {
        guard case let .integer(integer) = try evaluate(expression, in: environment) else {
            throw GooseInterpreterError.runtime(line: line, message: "Índice deve ser um inteiro")
        }
        guard integer.value >= 0, integer.value < Int64(count) else {
            throw GooseInterpreterError.runtime(
                line: line,
                message: "Índice \(integer.display) fora de um array de \(count) elementos"
            )
        }
        return Int(integer.value)
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
            let text = try arguments.map { try evaluate($0, in: environment).rendered }
            try append(text.joined() + "\n")
            return .null

        case "str":
            let text = try arguments.map { try evaluate($0, in: environment).rendered }
            return .string(text.joined())

        default:
            guard let function = program.functions[name] else {
                throw GooseInterpreterError.runtime(line: line, message: "Função desconhecida: \(name)")
            }
            return try call(function, arguments: try arguments.map { try evaluate($0, in: environment) }, line: line)
        }
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
            scope.declare(name, mutable: true, value: value)
        }

        callDepth += 1
        defer { callDepth -= 1 }

        do {
            return try executeBlock(function.body, in: scope)
        } catch let control as GooseReturn {
            return control.value
        }
    }

    private func callMethod(
        _ receiver: GooseExpression,
        name: String,
        arguments: [GooseExpression],
        in environment: GooseEnvironment,
        line: Int
    ) throws -> GooseValue {
        let target = try evaluate(receiver, in: environment)

        switch name {
        case "push", "append":
            guard case let .array(array) = target else {
                throw GooseInterpreterError.runtime(line: line, message: "\(name) existe apenas em arrays")
            }
            guard try isMutableRoot(receiver, in: environment) else {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "Não é possível alterar um array declarado com let"
                )
            }
            for argument in arguments {
                let value = try evaluate(argument, in: environment)
                if name == "append", case let .array(other) = value {
                    array.elements.append(contentsOf: other.elements)
                } else if name == "append", case let .string(text) = value {
                    array.elements.append(contentsOf: text.utf8.map { .integer(.literal(Int64($0))) })
                } else {
                    array.elements.append(value)
                }
            }
            return .null

        case "pop":
            guard case let .array(array) = target else {
                throw GooseInterpreterError.runtime(line: line, message: "pop existe apenas em arrays")
            }
            guard try isMutableRoot(receiver, in: environment) else {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "Não é possível alterar um array declarado com let"
                )
            }
            guard let last = array.elements.popLast() else {
                throw GooseInterpreterError.runtime(line: line, message: "pop em um array vazio")
            }
            return last

        default:
            throw GooseInterpreterError.runtime(line: line, message: "Método desconhecido: .\(name)")
        }
    }

    private func readField(
        _ receiver: GooseExpression,
        name: String,
        in environment: GooseEnvironment,
        line: Int
    ) throws -> GooseValue {
        switch (name, try evaluate(receiver, in: environment)) {
        case ("len", .array(let array)):
            return .integer(.literal(Int64(array.elements.count)))
        case ("len", .string(let text)):
            return .integer(.literal(Int64(text.utf8.count)))
        case ("cap", .array(let array)):
            return .integer(.literal(Int64(array.elements.count)))
        default:
            throw GooseInterpreterError.runtime(line: line, message: "Campo desconhecido: .\(name)")
        }
    }

    // MARK: Operators

    private func evaluateUnary(_ op: String, _ value: GooseValue, line: Int) throws -> GooseValue {
        switch (op, value) {
        case ("-", .integer(let integer)):
            return .integer(GooseInteger(value: 0 &- integer.value, bits: integer.bits,
                                         isSigned: integer.isSigned, isLiteral: false).normalized())
        case ("-", .double(let double)):
            return .double(-double)
        case ("+", let value):
            return value
        case ("!", .bool(let flag)):
            return .bool(!flag)
        default:
            throw GooseInterpreterError.runtime(
                line: line,
                message: "Operador '\(op)' inválido para \(value.rendered)"
            )
        }
    }

    private func evaluateBinary(
        _ op: String,
        _ left: GooseExpression,
        _ right: GooseExpression,
        line: Int,
        environment: GooseEnvironment
    ) throws -> GooseValue {
        // `&&` and `||` stop at the first decisive operand.
        if op == "&&" {
            return .bool(try isTrue(left, in: environment) && isTrue(right, in: environment))
        }
        if op == "||" {
            return .bool(try isTrue(left, in: environment) || isTrue(right, in: environment))
        }
        return try applyBinary(op, try evaluate(left, in: environment), try evaluate(right, in: environment), line: line)
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
        default:
            guard op == "==" || op == "!=" else {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "Operador '\(op)' inválido entre \(left.rendered) e \(right.rendered)"
                )
            }
            let equal = left.rendered == right.rendered
            return .bool(op == "==" ? equal : !equal)
        }
    }

    private func integerOperation(
        _ op: String,
        _ a: GooseInteger,
        _ b: GooseInteger,
        line: Int
    ) throws -> GooseValue {
        // An integer literal takes the width of the value it meets, so
        // `u8 + 1` wraps at 8 bits; two declared widths widen to the larger.
        let bits: Int
        let signed: Bool
        if a.isLiteral, !b.isLiteral {
            bits = b.bits
            signed = b.isSigned
        } else if b.isLiteral, !a.isLiteral {
            bits = a.bits
            signed = a.isSigned
        } else {
            bits = max(a.bits, b.bits)
            signed = a.bits == bits ? a.isSigned : b.isSigned
            if a.bits == b.bits, a.isSigned != b.isSigned, !a.isLiteral, !b.isLiteral,
               op != "==", op != "!=", op != "<", op != "<=", op != ">", op != ">=" {
                throw GooseInterpreterError.runtime(
                    line: line,
                    message: "Tipos com e sem sinal do mesmo tamanho não se misturam; converta com 'as'"
                )
            }
        }

        func result(_ value: Int64) -> GooseValue {
            .integer(GooseInteger(value: value, bits: bits, isSigned: signed, isLiteral: false).normalized())
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

    // MARK: Types

    private func coerce(_ value: GooseValue, to typeName: String, line: Int) throws -> GooseValue {
        if typeName.contains("[") {
            // `u8[>..]` is text; `u8[][>..]` and other nested arrays are not.
            if typeName.hasPrefix("u8["), typeName.filter { $0 == "[" }.count == 1,
               case let .array(array) = value {
                array.isByteArray = true
            }
            return value
        }
        guard let target = Self.integerTypes[typeName] else {
            switch typeName {
            case "f32", "f64":
                guard case let .integer(integer) = value else { return value }
                return .double(Double(integer.value))
            default:
                return value
            }
        }
        guard case let .integer(integer) = value else {
            throw GooseInterpreterError.runtime(line: line, message: "Esperado \(typeName), não \(value.rendered)")
        }
        return .integer(integer.converted(bits: target.bits, signed: target.signed))
    }

    private func cast(_ value: GooseValue, to typeName: String, line: Int) throws -> GooseValue {
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
        return .integer(integer.converted(bits: target.bits, signed: target.signed))
    }

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
