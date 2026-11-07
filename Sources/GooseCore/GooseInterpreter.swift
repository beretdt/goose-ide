import Foundation

/// Runs a subset of Goose locally, with no network and no compiler.
///
/// Supported: `fn` declarations, `let`/`var`, `if`/`while`/`for`, function
/// calls, recursion, arrays with `push`/`pop`/`append`, integer widths,
/// casts, and the `print`/`str` builtins. Structs, enums and slices are not
/// implemented yet.
public struct GooseInterpreter {
    public init() {}

    public func run(_ source: String) throws -> String {
        var lexer = GooseLexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = GooseParser(tokens: tokens)
        let program = try parser.parseProgram()
        return try GooseRuntime(program: program).run()
    }
}

public enum GooseInterpreterError: Error, Equatable, LocalizedError {
    case syntax(line: Int, message: String)
    case runtime(line: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case let .syntax(line, message):
            return "Linha \(line): \(message)"
        case let .runtime(line, message):
            return "Linha \(line): \(message)"
        }
    }
}
