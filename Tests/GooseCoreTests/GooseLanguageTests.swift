import XCTest
@testable import GooseCore

/// Every expectation in this file was produced by the reference Goose
/// compiler (v2026.4) running the same program, so the interpreter is
/// checked against the language and not against itself.
final class GooseLanguageTests: XCTestCase {
    private func run(_ source: String) throws -> String {
        try GooseInterpreter().run(source)
    }

    func testArithmeticMatchesReference() throws {
        let source = """
        fn main() {
            let answer = 42;
            var count: i32 = 0;
            count += 1;
            count++;
            print("answer=", answer, " count=", count);
            print(1 + 2 * 3, " ", (1 + 2) * 3, " ", 10 / 3, " ", 10 % 3);
            print(-7 % 3, " ", 7 % -3);
            print(0.75, " ", 1.5 + 2.25, " ", 1.0);
        }
        """

        XCTAssertEqual(
            try run(source),
            """
            answer=42 count=2
            7 9 3 1
            2 1
            0.75 3.75 1.0

            """
        )
    }

    func testIntegerWidthsMatchReference() throws {
        let source = """
        fn main() {
            let byte: u8 = 255;
            let wrapped: u8 = byte + 1;
            let widened = byte + 42;
            let narrowed = 300 as u8;
            print(wrapped, " ", widened, " ", narrowed);
            print((0 - 1) as u8);
        }
        """

        XCTAssertEqual(try run(source), "0 41 44\n255\n")
    }

    func testControlFlowMatchesReference() throws {
        let source = """
        fn main() {
            var total = 0;
            for i in 5 { total += i; }
            print("sum=", total);

            var n = 0;
            while n < 3 { n++; }
            print("n=", n);

            let kind = if total > 5 { "big" } else { "small" };
            print(kind);

            for i in 10 {
                if i % 2 == 0 { continue; }
                if i > 7 { break; }
                print("odd ", i);
            }
        }
        """

        XCTAssertEqual(
            try run(source),
            """
            sum=10
            n=3
            big
            odd 1
            odd 3
            odd 5
            odd 7

            """
        )
    }

    func testRecursionAndGenericParametersMatchReference() throws {
        let source = """
        recursive fn fib(n: i64) -> i64 {
            if n < 2 { return n; }
            return fib(n - 1) + fib(n - 2);
        }

        fn add(a, b) { a + b }

        fn main() {
            print(fib(10));
            print(add(2, 3), " ", add(2.5, 1.5));
        }
        """

        XCTAssertEqual(try run(source), "55\n5 4.0\n")
    }

    func testArraysMatchReference() throws {
        let source = """
        fn main() {
            var grow: i64[>..] = [];
            for i in 5 { grow.push(i * i); }
            print(grow);
            print(grow.len);

            var stack: i64[>..<] = [];
            stack.push(1); stack.push(2); stack.push(3);
            let top = stack.pop();
            print(top, " ", stack);

            let frozen: i64[] = [7, 8, 9];
            print(frozen, " ", frozen[1]);
            print(frozen[0] + frozen[2]);
        }
        """

        XCTAssertEqual(
            try run(source),
            """
            [0, 1, 4, 9, 16]
            5
            3 [1, 2]
            [7, 8, 9] 8
            16

            """
        )
    }

    func testStringsMatchReference() throws {
        let source = """
        fn main() {
            let greeting = "hello";
            print(greeting, " ", greeting.len);
            print(greeting == "hello", " ", greeting != "bye");
            print(str("x=", 42, " ok=", true));
            var s: u8[>..] = [];
            s.append("hi");
            s.push('!');
            print(s, " ", s.len);
        }
        """

        XCTAssertEqual(
            try run(source),
            """
            hello 5
            true true
            x=42 ok=true
            hi! 3

            """
        )
    }

    func testCommentsAreIgnored() throws {
        let source = """
        // a line comment
        fn main() {
            /* a block
               comment */
            print(1); // trailing
        }
        """

        XCTAssertEqual(try run(source), "1\n")
    }

    func testElseIfChainMatchesReference() throws {
        let source = """
        fn main() {
            for i in 16 {
                let word: u8[>..] = if i % 15 == 0 { "FizzBuzz" }
                    else if i % 3 == 0 { "Fizz" }
                    else if i % 5 == 0 { "Buzz" }
                    else { str(i) };
                print(word);
            }
        }
        """

        XCTAssertEqual(
            try run(source),
            """
            FizzBuzz
            1
            2
            Fizz
            4
            Buzz
            Fizz
            7
            8
            Fizz
            Buzz
            11
            Fizz
            13
            14
            FizzBuzz

            """
        )
    }

    // MARK: - Errors

    func testLetCannotBeReassigned() {
        XCTAssertThrowsError(try run("fn main() { let x = 1; x = 2; }")) { error in
            XCTAssertEqual(
                error as? GooseInterpreterError,
                .runtime(line: 1, message: "'x' foi declarado com let; use var para alterá-lo")
            )
        }
    }

    func testDivisionByZeroIsReported() {
        XCTAssertThrowsError(try run("fn main() { print(1 / 0); }")) { error in
            XCTAssertEqual(
                error as? GooseInterpreterError,
                .runtime(line: 1, message: "Divisão por zero")
            )
        }
    }

    func testIndexOutOfBoundsIsReported() {
        XCTAssertThrowsError(try run("fn main() { let xs = [1, 2]; print(xs[5]); }")) { error in
            guard case .runtime(_, let message) = error as? GooseInterpreterError else {
                return XCTFail("expected a runtime error, got \(error)")
            }
            XCTAssertTrue(message.contains("fora de um array"), message)
        }
    }

    func testUndefinedVariableIsReported() {
        XCTAssertThrowsError(try run("fn main() { print(nope); }")) { error in
            XCTAssertEqual(
                error as? GooseInterpreterError,
                .runtime(line: 1, message: "Variável não declarada: nope")
            )
        }
    }

    func testUnsupportedDeclarationsAreExplained() {
        XCTAssertThrowsError(try run("struct Point { x: i64 }")) { error in
            XCTAssertEqual(
                error as? GooseInterpreterError,
                .syntax(line: 1, message: "'struct' ainda não é suportado neste app")
            )
        }
    }

    func testRunawayLoopStopsInsteadOfHanging() {
        XCTAssertThrowsError(try run("fn main() { while true {} }")) { error in
            guard case .runtime(_, let message) = error as? GooseInterpreterError else {
                return XCTFail("expected a runtime error, got \(error)")
            }
            XCTAssertTrue(message.contains("passos"), message)
        }
    }

    func testDeepRecursionStopsInsteadOfCrashing() {
        let source = """
        recursive fn down(n: i64) -> i64 { return down(n + 1); }
        fn main() { print(down(0)); }
        """

        XCTAssertThrowsError(try run(source)) { error in
            guard case .runtime(_, let message) = error as? GooseInterpreterError else {
                return XCTFail("expected a runtime error, got \(error)")
            }
            XCTAssertTrue(message.contains("Recursão"), message)
        }
    }
}
