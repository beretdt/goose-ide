fn divide(a: i64, b: i64) -> i64, bool {
    if b == 0 { return 0, false; }
    return a / b, true;
}

fn show(n: i64) {
    guard n > 0;
    print("positivo: ", n);
}

fn main() {
    let q, ok = divide(7, 2);
    print(q, " ", ok);
    show(5);
    show(-1);

    defer print("fim");
    var xs: i64[>..] = [];
    for i in 4 { xs.push(i); }
    for &x in xs { x *= 2; }
    print(xs);
}
