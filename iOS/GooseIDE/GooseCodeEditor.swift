import SwiftUI
import UIKit

/// A monospaced editor with Goose syntax highlighting and a symbol bar
/// above the keyboard.
struct GooseCodeEditor: UIViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.inputAccessoryView = context.coordinator.makeSymbolBar(for: textView)
        textView.attributedText = GooseHighlighter.attributed(text: text)
        textView.typingAttributes = GooseHighlighter.baseAttributes
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.isEditable = isEditable
        guard textView.text != text else { return }

        let selection = textView.selectedRange
        textView.attributedText = GooseHighlighter.attributed(text: text)
        textView.typingAttributes = GooseHighlighter.baseAttributes
        textView.selectedRange = selection
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>
        private weak var textView: UITextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text

            // Re-highlighting keeps the caret where the user left it.
            let selection = textView.selectedRange
            textView.attributedText = GooseHighlighter.attributed(text: textView.text)
            textView.typingAttributes = GooseHighlighter.baseAttributes
            textView.selectedRange = selection
        }

        func makeSymbolBar(for textView: UITextView) -> UIView {
            self.textView = textView
            let symbols = ["\"", "(", ")", "[", "]", "{", "}", ";", "=", "+", "-", "<", ">"]
            let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
            toolbar.items = symbols.map {
                UIBarButtonItem(title: $0, style: .plain, target: self, action: #selector(insertSymbol(_:)))
            }
            toolbar.sizeToFit()
            return toolbar
        }

        @objc private func insertSymbol(_ sender: UIBarButtonItem) {
            guard let textView else { return }
            textView.insertText(sender.title ?? "")
            textViewDidChange(textView)
        }
    }
}

enum GooseHighlighter {
    static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
        .foregroundColor: UIColor.label,
    ]

    private static let keywords: Set<String> = [
        "fn", "recursive", "let", "var", "if", "else", "while", "for", "in",
        "return", "break", "continue", "as", "true", "false", "null", "match",
        "struct", "enum", "import", "const",
    ]

    private static let types: Set<String> = [
        "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64", "bool", "str",
    ]

    private static let rules: [(pattern: String, attributes: [NSAttributedString.Key: Any])] = [
        (
            #"//[^\n]*"#,
            [
                .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        ),
        (
            #""(?:\\.|[^"\\\n])*""#,
            [
                .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                .foregroundColor: UIColor.systemRed,
            ]
        ),
        (
            #"\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#,
            [
                .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                .foregroundColor: UIColor.systemTeal,
            ]
        ),
    ]

    static func attributed(text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes)
        let full = NSRange(location: 0, length: (text as NSString).length)

        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            for match in regex.matches(in: text, range: full) {
                result.addAttributes(rule.attributes, range: match.range)
            }
        }

        applyWords(text, into: result)
        return result
    }

    /// Colours keywords, builtin types and the name a `fn` declares.
    private static func applyWords(_ text: String, into result: NSMutableAttributedString) {
        let nsText = text as NSString
        var identifier = ""
        var identifierStart = 0

        func colour(_ word: String, at start: Int) {
            guard !word.isEmpty else { return }
            let range = NSRange(location: start, length: word.count)
            if keywords.contains(word) {
                result.addAttributes(
                    [
                        .foregroundColor: UIColor.systemPink,
                        .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .semibold),
                    ],
                    range: range
                )
            } else if types.contains(word) {
                result.addAttributes(
                    [.foregroundColor: UIColor.systemPurple],
                    range: range
                )
            } else if previousWord(before: start, in: nsText) == "fn" {
                result.addAttributes(
                    [.foregroundColor: UIColor.systemBlue],
                    range: range
                )
            }
        }

        for index in 0..<nsText.length {
            let character = nsText.character(at: index)
            let isWordCharacter = (character >= 65 && character <= 90)
                || (character >= 97 && character <= 122)
                || (character >= 48 && character <= 57)
                || character == 95

            if isWordCharacter {
                if identifier.isEmpty { identifierStart = index }
                if let scalar = UnicodeScalar(character) {
                    identifier.append(Character(scalar))
                }
            } else if !identifier.isEmpty {
                colour(identifier, at: identifierStart)
                identifier = ""
            }
        }
        colour(identifier, at: identifierStart)
    }

    private static func previousWord(before index: Int, in text: NSString) -> String? {
        var cursor = index - 1
        while cursor >= 0, text.character(at: cursor) == 32 || text.character(at: cursor) == 9 {
            cursor -= 1
        }
        let end = cursor
        while cursor >= 0 {
            let character = text.character(at: cursor)
            let isWord = (character >= 97 && character <= 122) || (character >= 65 && character <= 90)
            if !isWord { break }
            cursor -= 1
        }
        guard end >= cursor + 1 else { return nil }
        return text.substring(with: NSRange(location: cursor + 1, length: end - cursor))
    }
}
