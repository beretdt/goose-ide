import XCTest
@testable import GooseCore

/// Structs, enums and `match`, with every expectation taken from the
/// reference Goose compiler (v2026.4) running the same program.
final class GooseCompositeTests: XCTestCase {
    private func run(_ source: String) throws -> String {
        try GooseInterpreter().run(source)
    }

    private let shapes = """
    struct Point { x: f64, y: f64 }
    struct Player { name: u8[..16], pos: Point, hp: i32 = 100, alive: bool = true }

    enum Shape { Circle { r: f64 }, Rect { w: f64, h: f64 }, Dot }
    """

    func testStructLiteralAndFieldsMatchReference() throws {
        let source = shapes + """

        fn main() {
            var p = Player { name: "gus", pos: Point { 1.0, 2.0 } };
            print(p);
            print(p.name, "|", p.pos.x, "|", p.hp, "|", p.alive);
            p.hp -= 30;
            p.pos = p.pos + Point { 0.5, 0.5 };
            print(p);
            print(p.name, " at ", p.pos.x, ",", p.pos.y, " hp ", p.hp);
        }
        """

        XCTAssertEqual(
            try run(source),
            """
            Player { "gus", Point { 1.0, 2.0 }, 100, true }
            gus|1.0|100|true
            Player { "gus", Point { 1.5, 2.5 }, 70, true }
            gus at 1.5,2.5 hp 70

            """
        )
    }

    func testPositionalFieldsAndDefaultsMatchReference() throws {
        let source = shapes + """

        fn main() {
            let p = Player { name: "ada", pos: Point { 1.0, 2.0 } };
            print(p);
            let q = Player { name: "x", pos: Point { 0.0, 0.0 }, hp: 5 };
            print(q);
        }
        """

        XCTAssertEqual(
            try run(source),
            """
            Player { "ada", Point { 1.0, 2.0 }, 100, true }
            Player { "x", Point { 0.0, 0.0 }, 5, true }

            """
        )
    }

    func testEnumValuesMatchReference() throws {
        let source = shapes + """

        fn main() {
            var shapes: Shape[>..] = [];
            shapes.push(Shape.Circle { r: 1.0 });
            shapes.push(Shape.Rect { w: 2.0, h: 3.0 });
            shapes.push(Shape.Dot);
            print(shapes);

            for s in shapes {
                match s {
                    Circle c => print("circle r=", c.r),
                    Rect r => print("rect ", r.w, "x", r.h),
                    _ => print("dot"),
                }
            }

            print(Shape.Dot);
            print(Shape.Circle { r: 2.0 });
        }
        """

        XCTAssertEqual(
            try run(source),
            """
            [Circle { 1.0 }, Rect { 2.0, 3.0 }, Shape.Dot]
            circle r=1.0
            rect 2.0x3.0
            dot
            Shape.Dot
            Circle { 2.0 }

            """
        )
    }

    func testMatchOnIntegersAndRangesMatchesReference() throws {
        let source = """
        fn main() {
            let level = match 42 { 0 => "zero", 1..50 => "low", _ => "high" };
            print(level, " ", match 7 { 0 => "zero", 1..50 => "low", _ => "high" });
        }
        """

        XCTAssertEqual(try run(source), "low low\n")
    }

    func testMatchBindsVariantPayloads() throws {
        let source = shapes + """

        fn kind(s: Shape) -> u8[:] {
            match s {
                Circle, Dot => "round",
                Rect r => if r.w == r.h { "square" } else { "rectangle" },
            }
        }

        fn main() {
            print(kind(Shape.Dot), " ", kind(Shape.Rect { w: 2.0, h: 2.0 }));
            print(kind(Shape.Rect { w: 2.0, h: 3.0 }));
        }
        """

        XCTAssertEqual(try run(source), "round square\nrectangle\n")
    }

    func testSlicesMatchReference() throws {
        let source = """
        fn total(xs: i64[:]) -> i64 { var t = 0; for x in xs { t += x; } return t; }

        fn main() {
            var grow: i64[>..] = [];
            for i in 5 { grow.push(i); }
            print(grow[1..4], " ", grow[^2..], " ", total(grow), " ", total(grow[1..4]));

            let xs = [1, 2, 3];
            print(xs[..], " ", xs[..2]);
        }
        """

        XCTAssertEqual(try run(source), "[1, 2, 3] [3, 4] 10 6\n[1, 2, 3] [1, 2]\n")
    }

    func testForOverRangeMatchesReference() throws {
        let source = """
        fn main() {
            var acc = 0;
            for i in 10..13 { acc += i; }
            print(acc);
        }
        """

        XCTAssertEqual(try run(source), "33\n")
    }

    func testStructCopyIsAValueMatchReference() throws {
        let source = """
        struct Point { x: f64, y: f64 }

        fn main() {
            let a = Point { 1.0, 2.0 };
            var b = a;
            b.x = 9.0;
            print(a.x, " ", b.x);

            var ps: Point[>..] = [];
            ps.push(Point { 3.0, 4.0 });
            print(ps[0].y);
            ps[0].x = 7.0;
            print(ps);
        }
        """

        XCTAssertEqual(
            try run(source),
            "1.0 9.0\n4.0\n[Point { 7.0, 4.0 }]\n"
        )
    }

    func testEnumsWithAreasAndStructSlicesMatchReference() throws {
        let source = """
        struct Point { x: f64, y: f64 }
        enum Shape { Circle { r: f64 }, Rect { w: f64, h: f64 }, Dot }

        fn area(s: Shape) -> f64 {
            match s {
                Circle c => 3.14159 * c.r * c.r,
                Rect r => r.w * r.h,
                Dot => 0.0,
            }
        }

        fn main() {
            var shapes: Shape[>..] = [];
            shapes.push(Shape.Circle { r: 1.0 });
            shapes.push(Shape.Rect { w: 2.0, h: 3.0 });
            shapes.push(Shape.Dot);
            for s in shapes { print(s, " area ", area(s)); }

            var pts: Point[>..] = [];
            for i in 4 { pts.push(Point { (i as f64), (i as f64) * 2.0 }); }
            print(pts);
            print(pts[1..3]);
        }
        """

        XCTAssertEqual(
            try run(source),
            """
            Circle { 1.0 } area 3.14159
            Rect { 2.0, 3.0 } area 6.0
            Shape.Dot area 0.0
            [Point { 0.0, 0.0 }, Point { 1.0, 2.0 }, Point { 2.0, 4.0 }, Point { 3.0, 6.0 }]
            [Point { 1.0, 2.0 }, Point { 2.0, 4.0 }]

            """
        )
    }

    // MARK: - Errors
    func testMatchWithoutAMatchingArmIsReported() {
        XCTAssertThrowsError(try run("fn main() { print(match 5 { 0 => 1 }); }")) { error in
            guard case .runtime(_, let message) = error as? GooseInterpreterError else {
                return XCTFail("expected a runtime error, got \(error)")
            }
            XCTAssertTrue(message.contains("match sem braço"), message)
        }
    }

    func testUnknownFieldIsReported() {
        let source = """
        struct Point { x: f64 }
        fn main() { let p = Point { 1.0 }; print(p.y); }
        """

        XCTAssertThrowsError(try run(source)) { error in
            guard case .runtime(_, let message) = error as? GooseInterpreterError else {
                return XCTFail("expected a runtime error, got \(error)")
            }
            XCTAssertTrue(message.contains("não tem o campo 'y'"), message)
        }
    }

    func testMissingRequiredFieldIsReported() {
        let source = """
        struct Point { x: f64, y: f64 }
        fn main() { let p = Point { x: 1.0 }; print(p); }
        """

        XCTAssertThrowsError(try run(source)) { error in
            guard case .runtime(_, let message) = error as? GooseInterpreterError else {
                return XCTFail("expected a runtime error, got \(error)")
            }
            XCTAssertTrue(message.contains("precisa do campo 'y'"), message)
        }
    }
}
