import XCTest
@testable import GooseCore

final class GooseInterpreterTests: XCTestCase {
    func testRunsHelloGooseMainFunction() throws {
        let source = """
        fn main() {
            print("Hello, Goose!");
        }
        """

        XCTAssertEqual(try GooseInterpreter().run(source), "Hello, Goose!\n")
    }

    func testPrintsMultipleValuesWithoutSeparators() throws {
        XCTAssertEqual(
            try GooseInterpreter().run("fn main() { print(\"Answer: \", 42, true); }"),
            "Answer: 42true\n"
        )
    }

    func testDecodesEscapedCharacters() throws {
        XCTAssertEqual(
            try GooseInterpreter().run("print(\"one\\ntwo\");"),
            "one\ntwo\n"
        )
    }

    func testReportsInvalidSyntax() {
        XCTAssertThrowsError(try GooseInterpreter().run("fn main() { print(42)")) { error in
            XCTAssertEqual(
                error as? GooseInterpreterError,
                .syntax(line: 1, message: "Bloco sem fechamento")
            )
        }
    }
}
