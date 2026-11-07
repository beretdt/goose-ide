// 06_strings.goose
fn main() {
    let greeting = "hello";
    print(greeting, " ", greeting.len);
    print(greeting == "hello", " ", greeting != "bye");
    print(str("x=", 42, " ok=", true));
    var s: u8[>..] = [];
    s.append("hi");
    s.push('!');
    print(s, " ", s.len);
}
