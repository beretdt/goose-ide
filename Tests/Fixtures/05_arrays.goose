// 05_arrays.goose
fn main() {
    var grow: i64[>..] = [];
    for i in 5 { grow.push(i * i); }
    print(grow);
    print(grow.len);

    var stack: i64[>..<] = [];
    stack.push(1); stack.push(2); stack.push(3);
    let top = stack.pop();
    print(top, " ", stack);

    let frozen: i64[] = [7, 8, 9];
    print(frozen, " ", frozen[1]);
    print(frozen[0] + frozen[2]);
}
