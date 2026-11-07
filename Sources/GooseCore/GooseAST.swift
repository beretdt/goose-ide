import Foundation

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
    case block([GooseStatement], line: Int)
    case cast(GooseExpression, String, checked: Bool, line: Int)

    var line: Int {
        switch self {
        case let .integer(_, line), let .double(_, line), let .boolean(_, line),
             let .string(_, line), let .null(line), let .variable(_, line):
            return line
        case let .unary(_, _, line), let .binary(_, _, _, line),
             let .call(_, _, line), let .method(_, _, _, line),
             let .field(_, _, line), let .index(_, _, line),
             let .arrayLiteral(_, line), let .arrayFill(_, _, line),
             let .conditional(_, _, _, line), let .block(_, line),
             let .cast(_, _, _, line):
            return line
        }
    }
}

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

struct GooseFunction {
    let name: String
    let parameters: [String]
    let body: [GooseStatement]
    let line: Int
}

struct GooseProgram {
    let functions: [String: GooseFunction]
    let statements: [GooseStatement]
}
