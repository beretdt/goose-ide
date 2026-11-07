import XCTest
@testable import GooseCore

/// Control flow, multiple results and the builtins that were added after the
/// first pass. Every expectation comes from the reference Goose compiler
/// (v2026.4) running the same program.
final class GooseControlFlowTests: XCTestCase {
    private func run(_ source: String) throws -> String {
        try GooseInterpreter().run(source)
    }

    func testLoopAndBlockWithGuardMatchReference() throws {
        let source = """
        fn main() {
            var n = 5;
            loop { n--; if n == 0 { break; } }
            print("n=", n);

            let verdict = block {
                guard n == 0 else { break "ainda tem"; }
                "zerado"
            };
            print(verdict);

            var s: i64[>..] = [];
            var out: u8[>..] = [];
            format(out, "x=", 1, " y=", 2.5);
            print(out);
        }
        """

        XCTAssertEqual(
            try run(source),
            """
            n=0
            zerado
            x=1 y=2.5

            """
        )
    }

    func testDeferRunsAtScopeExitInReverse() throws {
        let source = """
        fn main() {
            defer print("primeiro");
            defer print("segundo");
            print("agora");
        }
        """

        XCTAssertEqual(try run(source), "agora\nsegundo\nprimeiro\n")
    }

    func testDeferRunsEvenWhenTheScopeReturns() throws {
        let source = """
        fn work() -> i64 {
            defer print("limpando");
            return 7;
        }

        fn main() {
            print(work());
        }
        """

        XCTAssertEqual(try run(source), "limpando\n7\n")
    }

    func testMultipleResultsMatchReference() throws {
        let source = """
        fn divide(a: i64, b: i64) -> i64, bool {
            if b == 0 { return 0, false; }
            return a / b, true;
        }

        fn three() -> i64, i64, i64 { return 1, 2, 3; }

        fn main() {
            let q, ok = divide(7, 2);
            print(q, " ", ok);
            let z, ok2 = divide(1, 0);
            print(z, " ", ok2);

            let x, y, w = three();
            print(x, y, w);
        }
        """

        XCTAssertEqual(try run(source), "3 true\n0 false\n123\n")
    }

    func testMultipleResultsAssignIntoExistingVariables() throws {
        let source = """
        fn divide(a: i64, b: i64) -> i64, bool {
            if b == 0 { return 0, false; }
            return a / b, true;
        }

        fn main() {
            var q = 0;
            var ok = false;
            q, ok = divide(9, 3);
            print(q, " ", ok);
        }
        """

        XCTAssertEqual(try run(source), "3 true\n")
    }

    func testOptionalsMatchReference() throws {
        let source = """
        fn first_at_least(xs: i64[:], min: i64) -> i64? {
            for &x in xs { if x >= min { return x; } }
            return null;
        }

        fn main() {
            let xs = [1, 5, 9];
            let a = first_at_least(xs, 5);
            let b = first_at_least(xs, 99);
            print(a, " | ", b);
            print(a == null, " ", b == null);
            if b == null { print("nada"); }
        }
        """

        XCTAssertEqual(
            try run(source),
            """
            5 | null
            false true
            nada

            """
        )
    }

    func testForByReferenceWritesBack() throws {
        let source = """
        fn main() {
            var xs: i64[>..] = [];
            for i in 4 { xs.push(i); }
            for &x in xs { x *= 2; }
            print(xs);
        }
        """

        XCTAssertEqual(try run(source), "[0, 2, 4, 6]\n")
    }

    /// `guard c;` runs the rest of the block only where `c` holds. Goose
    /// rejects it where a value is required, so this program is the shape the
    /// reference compiler accepts.
    func testGuardWithoutElseSkipsTheRestOfTheBlock() throws {
        let source = """
        fn show(n: i64) {
            guard n > 0;
            print("positivo ", n);
        }

        fn main() {
            show(5);
            show(-1);
        }
        """

        XCTAssertEqual(try run(source), "positivo 5\n")
    }

    func testFormatAppendsToAByteArray() throws {
        let source = """
        fn main() {
            var out: u8[>..] = [];
            format(out, "a", 1);
            print(out.len);
            format(out, " b", 2.5);
            print(out);
        }
        """

        XCTAssertEqual(try run(source), "2\na1 b2.5\n")
    }

    // MARK: - Errors

    func testBreakOutsideLoopAndBlockIsRejected() {
        XCTAssertThrowsError(try run("fn main() { break; }")) { error in
            guard case .syntax(_, let message) = error as? GooseInterpreterError else {
                return XCTFail("expected a syntax error, got \(error)")
            }
            XCTAssertTrue(message.contains("'break'"), message)
        }
    }

    func testGuardElseThatDoesNotLeaveIsReported() {
        let source = """
        fn main() {
            let value = block {
                guard false else { print("oi"); }
                "ok"
            };
            print(value);
        }
        """

        XCTAssertThrowsError(try run(source)) { error in
            guard case .runtime(_, let message) = error as? GooseInterpreterError else {
                return XCTFail("expected a runtime error, got \(error)")
            }
            XCTAssertTrue(message.contains("guard"), message)
        }
    }

    func testWrongNumberOfNamesIsReported() {
        let source = """
        fn two() -> i64, i64 { return 1, 2; }
        fn main() { let a, b, c = two(); print(a); }
        """

        XCTAssertThrowsError(try run(source)) { error in
            guard case .runtime(_, let message) = error as? GooseInterpreterError else {
                return XCTFail("expected a runtime error, got \(error)")
            }
            XCTAssertTrue(message.contains("resultado"), message)
        }
    }

    func testRunawayLoopIsStopped() {
        XCTAssertThrowsError(try run("fn main() { loop {} }")) { error in
            guard case .runtime(_, let message) = error as? GooseInterpreterError else {
                return XCTFail("expected a runtime error, got \(error)")
            }
            XCTAssertTrue(message.contains("passos"), message)
        }
    }
}
