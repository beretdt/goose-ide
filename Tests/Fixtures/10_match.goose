struct Point { x: f64, y: f64 }
struct Player { name: u8[..16], pos: Point, hp: i32 = 100, alive: bool = true }

enum Shape { Circle { r: f64 }, Rect { w: f64, h: f64 }, Dot }

fn main() {
    var p = Player { name: "gus", pos: Point { 1.0, 2.0 } };
    print(p);
    print(p.name, "|", p.pos.x, "|", p.hp, "|", p.alive);

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

    let level = match 42 { 0 => "zero", 1..50 => "low", _ => "high" };
    print(level);
}
