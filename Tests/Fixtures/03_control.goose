// 03_control.goose
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
