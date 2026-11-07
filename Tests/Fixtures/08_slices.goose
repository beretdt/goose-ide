fn total(xs: i64[:]) -> i64 {
    var t = 0;
    for x in xs { t += x; }
    return t;
}
fn main() {
    var grow: i64[>..] = [];
    for i in 5 { grow.push(i); }
    print("tudo: ", grow, " soma ", total(grow));
    print("1..4: ", grow[1..4], " soma ", total(grow[1..4]));
    print("últimos 2: ", grow[^2..]);
    for i in 10..13 { print("faixa ", i); }
}
