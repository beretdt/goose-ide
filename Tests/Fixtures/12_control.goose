fn main() {
    var n = 5;
    loop { n--; if n == 0 { break; } }
    print("n=", n);

    let verdict = block {
        guard n == 0 else { break "ainda tem"; }
        "zerado"
    };
    print(verdict);

    var s: u8[>..] = [];
    format(s, "x=", 1, " y=", 2.5);
    print(s);

    defer print("depois");
    print("antes");
}
