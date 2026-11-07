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
