struct Point { x: f64, y: f64 }
struct Player { name: u8[..16], pos: Point, hp: i32 = 100, alive: bool = true }

fn main() {
    var p = Player { name: "gus", pos: Point { 1.0, 2.0 } };
    print(p);
    p.hp -= 30;
    p.pos = p.pos + Point { 0.5, 0.5 };
    print(p);
    print(p.name, " at ", p.pos.x, ",", p.pos.y, " hp ", p.hp);
}
