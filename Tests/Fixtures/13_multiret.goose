fn first_at_least(xs: i64[:], min: i64) -> i64? {
    for &x in xs { if x >= min { return x; } }
    return null;
}
fn three() -> i64, i64, i64 { return 1, 2, 3; }
fn main() {
    let xs = [1, 5, 9];
    let a = first_at_least(xs, 5);
    let b = first_at_least(xs, 99);
    print(a, " | ", b);
    print(a == null, " ", b == null);
    let x, y, z = three();
    print(x, y, z);
    var s: u8[>..] = [];
    format(s, "a", 1, " b", 2.5);
    print(s, " len=", s.len);
}
