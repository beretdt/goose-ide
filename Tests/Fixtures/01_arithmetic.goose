// 01_arithmetic.goose
fn main() {
    let answer = 42;
    var count: i32 = 0;
    count += 1;
    count++;
    print("answer=", answer, " count=", count);
    print(1 + 2 * 3, " ", (1 + 2) * 3, " ", 10 / 3, " ", 10 % 3);
    print(-7 % 3, " ", 7 % -3);
    print(0.75, " ", 1.5 + 2.25, " ", 1.0);
}
