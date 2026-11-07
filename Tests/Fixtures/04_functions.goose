// 04_functions.goose
recursive fn fib(n: i64) -> i64 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}

fn add(a, b) { a + b }

fn main() {
    print(fib(10));
    print(add(2, 3), " ", add(2.5, 1.5));
}
