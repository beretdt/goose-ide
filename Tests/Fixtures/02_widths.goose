// 02_widths.goose
fn main() {
    let byte: u8 = 255;
    let wrapped: u8 = byte + 1;
    let widened = byte + 42;
    let narrowed = 300 as u8;
    print(wrapped, " ", widened, " ", narrowed);
    print(byte as i32, " ", (0 - 1) as u8);
}
