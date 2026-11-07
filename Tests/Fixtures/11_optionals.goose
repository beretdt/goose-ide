fn divide(a: i64, b: i64) -> i64, bool {
    if b == 0 { return 0, false; }
    return a / b, true;
}

fn first_at_least(xs: i64[:], min: i64) -> i64? {
    for &x in xs { if x >= min { return x; } }
    return null;
}

fn main() {
    let q, ok = divide(7, 2);
    print(q, " ", ok);
    let z, ok2 = divide(1, 0);
    print(z, " ", ok2);

    let xs = [1, 5, 9];
    let found = first_at_least(xs, 5);
    print(found);
    if found != null { print("achou ", found); }
}
