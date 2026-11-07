import Foundation

// MARK: - Declarations

struct GooseFieldDecl {
    let name: String
    let typeName: String?
    let defaultValue: GooseExpression?
}

struct GooseStructDecl {
    let name: String
    let fields: [GooseFieldDecl]
    let line: Int
}

struct GooseVariantDecl {
    let name: String
    let fields: [GooseFieldDecl]
}

struct GooseEnumDecl {
    let name: String
    let variants: [GooseVariantDecl]
    let line: Int
}

struct GooseFunction {
    let name: String
    let parameters: [String]
    let body: [GooseStatement]
    let line: Int
}

struct GooseProgram {
    let functions: [String: GooseFunction]
    let structs: [String: GooseStructDecl]
    let enums: [String: GooseEnumDecl]
    let statements: [GooseStatement]
}

// MARK: - Patterns

enum GoosePattern {
    case wildcard
    case variant(String, binder: String?)
    case integer(Int64)
    case range(Int64, Int64)
}

struct GooseMatchArm {
    let patterns: [GoosePattern]
    let body: [GooseStatement]
}

/// An argument of a struct or variant literal, named or positional.
struct GooseNamedArgument {
    let name: String?
    let value: GooseExpression
}

// MARK: - Expressions

indirect enum GooseExpression {
    case integer(String, line: Int)
    case double(Double, line: Int)
    case boolean(Bool, line: Int)
    case string(String, line: Int)
    case null(line: Int)
    case variable(String, line: Int)
    case unary(String, GooseExpression, line: Int)
    case binary(String, GooseExpression, GooseExpression, line: Int)
    case call(String, [GooseExpression], line: Int)
    case method(GooseExpression, String, [GooseExpression], line: Int)
    case field(GooseExpression, String, line: Int)
    case index(GooseExpression, GooseExpression, line: Int)
    case arrayLiteral([GooseExpression], line: Int)
    case arrayFill(GooseExpression, GooseExpression, line: Int)
    case conditional(GooseExpression, [GooseStatement], [GooseStatement]?, line: Int)
    case match(GooseExpression, [GooseMatchArm], line: Int)
    case block([GooseStatement], line: Int)
    case cast(GooseExpression, String, checked: Bool, line: Int)
    /// `Type { 1, 2 }` or `Type { field: 1 }`.
    case structLiteral(String, [GooseNamedArgument], line: Int)
    /// `Enum.Variant { … }`, or `Enum.Variant` when the payload is empty.
    case variantLiteral(String, String, [GooseNamedArgument], line: Int)
    /// `a[1..4]`, `a[^2..]`, `a[..]`.
    case slice(GooseExpression, GooseExpression?, GooseExpression?, line: Int)
    /// `^n`, which counts from the end of a slice's array.
    case fromEnd(GooseExpression, line: Int)
    /// `a..b` in a `for`, exclusive of `b`.
    case range(GooseExpression, GooseExpression, line: Int)

    var line: Int {
        switch self {
        case let .integer(_, line), let .double(_, line), let .boolean(_, line),
             let .string(_, line), let .null(line), let .variable(_, line):
            return line
        case let .unary(_, _, line), let .binary(_, _, _, line),
             let .call(_, _, line), let .method(_, _, _, line),
             let .field(_, _, line), let .index(_, _, line),
             let .arrayLiteral(_, line), let .arrayFill(_, _, line),
             let .conditional(_, _, _, line), let .match(_, _, line),
             let .block(_, line), let .cast(_, _, _, line),
             let .structLiteral(_, _, line), let .variantLiteral(_, _, _, line),
             let .slice(_, _, _, line), let .fromEnd(_, line), let .range(_, _, line):
            return line
        }
    }
}

// MARK: - Statements

indirect enum GooseStatement {
    case declare(name: String, mutable: Bool, typeName: String?, value: GooseExpression, line: Int)
    case assign(target: GooseExpression, op: String, value: GooseExpression, line: Int)
    case expression(GooseExpression)
    case loopWhile(GooseExpression, [GooseStatement], line: Int)
    case forEach(name: String, iterable: GooseExpression, body: [GooseStatement], line: Int)
    case returnValue(GooseExpression?, line: Int)
    case breakLoop(line: Int)
    case continueLoop(line: Int)
}
