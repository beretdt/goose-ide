import SwiftUI
import UIKit

/// A VS Code-style editor: Dark+ colours, a line-number gutter, and a symbol
/// bar above the keyboard.
struct GooseCodeEditor: UIViewRepresentable {
    @Binding var text: String
    var language: CodeLanguage = .goose
    var isEditable = true

    func makeUIView(context: Context) -> EditorContainerView {
        let container = EditorContainerView()
        container.textView.delegate = context.coordinator
        container.onTextChange = { newText in
            context.coordinator.text.wrappedValue = newText
        }
        container.applyModelText(text, language: language)
        return container
    }

    func updateUIView(_ container: EditorContainerView, context: Context) {
        container.textView.isEditable = isEditable
        container.applyModelText(text, language: language)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let text: Binding<String>
        private var pendingEditRange: NSRange?

        init(text: Binding<String>) {
            self.text = text
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            pendingEditRange = NSRange(
                location: range.location,
                length: (replacement as NSString).length
            )
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            let changedRange = pendingEditRange
            pendingEditRange = nil
            (textView.superview as? EditorContainerView)?.textChanged(changedRange: changedRange)
        }
    }
}

/// The text view plus its gutter, wired so both scroll together.
final class EditorContainerView: UIView {
    let textView = UITextView()
    private let gutter = LineNumberGutter()
    private var isApplyingModelText = false
    private var lastMarksOffset: CGFloat = 0
    private var language: CodeLanguage = .goose

    var onTextChange: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(VSCode.editorBackground)

        gutter.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gutter)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.textColor = UIColor(VSCode.text)
        textView.tintColor = UIColor(VSCode.statusBar)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 24, right: 8)
        textView.typingAttributes = GooseHighlighter.baseAttributes
        textView.inputAccessoryView = SymbolBar.make(target: self, action: #selector(insertSymbol(_:)))
        textView.accessibilityIdentifier = "sourceEditor"
        addSubview(textView)

        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutter.topAnchor.constraint(equalTo: topAnchor),
            gutter.bottomAnchor.constraint(equalTo: bottomAnchor),
            gutter.widthAnchor.constraint(equalToConstant: 34),

            textView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        textView.addObserver(self, forKeyPath: "contentOffset", options: [.new], context: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        textView.removeObserver(self, forKeyPath: "contentOffset")
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == "contentOffset" else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        let offset = textView.contentOffset.y
        gutter.scrollOffset = offset

        // The marks only cover a window around where they were computed, so a
        // long scroll refreshes them instead of leaving gaps in the gutter.
        if abs(offset - lastMarksOffset) > 300 {
            gutter.marks = lineMarks()
        }
    }

    /// Called by the model, so typing does not fight the binding.
    func applyModelText(_ newText: String, language newLanguage: CodeLanguage) {
        let current = textView.text ?? ""
        guard current != newText || language != newLanguage else { return }
        language = newLanguage
        isApplyingModelText = true

        let selection = textView.selectedRange
        let offset = textView.contentOffset
        textView.attributedText = GooseHighlighter.attributed(text: newText, language: language)
        textView.typingAttributes = GooseHighlighter.baseAttributes

        let limit = (newText as NSString).length
        let location = min(selection.location, limit)
        textView.selectedRange = NSRange(
            location: location,
            length: min(selection.length, limit - location)
        )
        // Assigning text resets the scroll position; put it back.
        textView.setContentOffset(offset, animated: false)

        isApplyingModelText = false
        refreshGutter()
    }

    /// Called by the delegate after the user types.
    func textChanged(changedRange: NSRange? = nil) {
        guard !isApplyingModelText else { return }

        let selection = textView.selectedRange
        let plain = textView.text ?? ""
        GooseHighlighter.applyIncremental(
            to: textView.textStorage,
            text: plain as NSString,
            changedRange: changedRange ?? NSRange(location: selection.location, length: 0),
            language: language
        )
        textView.typingAttributes = GooseHighlighter.baseAttributes

        onTextChange?(plain)
        refreshGutter()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshGutter()
    }

    private func refreshGutter() {
        gutter.marks = lineMarks()
        gutter.scrollOffset = textView.contentOffset.y
        lastMarksOffset = textView.contentOffset.y
    }

    /// One mark per logical line, at the y of that line's first fragment.
    /// A wrapped continuation keeps its line's number, as in VS Code.
    private func lineMarks() -> [LineNumberGutter.Mark] {
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        let text = textView.text ?? ""
        guard !text.isEmpty, layoutManager.numberOfGlyphs > 0 else {
            return [LineNumberGutter.Mark(number: 1, y: 0)]
        }

        let nsText = text as NSString
        let inset = textView.textContainerInset

        // `bounds.origin` is the scroll offset in a scroll view, so this maps
        // the visible area into textContainer coordinates, then widens it so a
        // small scroll does not have to redo the work.
        var area = textView.bounds
        area.origin.x -= inset.left
        area.origin.y -= inset.top
        area = area.insetBy(dx: 0, dy: -600)

        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: area, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        let startCharacter = characterRange.location

        // A line number is 1 + the newlines before its first character.
        var newlinesBeforeStart = 0
        var index = 0
        while index < startCharacter {
            if nsText.character(at: index) == 10 { newlinesBeforeStart += 1 }
            index += 1
        }
        let startsAtLineBoundary = startCharacter == 0 || nsText.character(at: startCharacter - 1) == 10

        var marks: [LineNumberGutter.Mark] = []
        var nextNumber: Int? = startsAtLineBoundary ? newlinesBeforeStart + 1 : nil

        layoutManager.enumerateLineFragments(forGlyphRange: visibleGlyphs) { rect, _, _, glyphRange, _ in
            let fragmentStart = layoutManager
                .characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil).location
            let startsLine = fragmentStart == 0 || nsText.character(at: fragmentStart - 1) == 10
            guard startsLine else { return }

            let number = nextNumber ?? (1 + Self.newlines(before: fragmentStart, in: nsText))
            nextNumber = number + 1
            marks.append(LineNumberGutter.Mark(number: number, y: rect.minY + inset.top))
        }

        return marks.isEmpty ? [LineNumberGutter.Mark(number: 1, y: 0)] : marks
    }

    private static func newlines(before index: Int, in text: NSString) -> Int {
        var total = 0
        var cursor = 0
        while cursor < index {
            if text.character(at: cursor) == 10 { total += 1 }
            cursor += 1
        }
        return total
    }

    @objc private func insertSymbol(_ sender: UIButton) {
        guard let symbol = sender.title(for: .normal) else { return }
        textView.insertText(symbol == "−" ? "-" : symbol)
        textChanged()
    }
}

/// Draws the line numbers; the container keeps it in step with the text view.
final class LineNumberGutter: UIView {
    struct Mark {
        let number: Int
        let y: CGFloat
    }

    var marks: [Mark] = [] {
        didSet { setNeedsDisplay() }
    }

    var scrollOffset: CGFloat = 0 {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(VSCode.gutter)
        isOpaque = true
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setFillColor(UIColor(VSCode.gutter).cgColor)
        context.fill(bounds)

        // The hairline VS Code draws between the gutter and the code.
        context.setFillColor(UIColor(VSCode.panelBorder).cgColor)
        context.fill(CGRect(x: bounds.width - 0.5, y: 0, width: 0.5, height: bounds.height))

        let attributes: [NSAttributedString.Key: Any] = [
            .font: VSCode.gutterFont,
            .foregroundColor: UIColor(VSCode.gutterText),
        ]
        let inset: CGFloat = 8

        for mark in marks {
            let text = "\(mark.number)" as NSString
            let size = text.size(withAttributes: attributes)
            let y = mark.y - scrollOffset + (VSCode.lineHeight - size.height) / 2
            guard y > -30, y < bounds.height + 30 else { continue }
            text.draw(
                at: CGPoint(x: bounds.width - inset - size.width, y: y),
                withAttributes: attributes
            )
        }
    }
}

/// The symbol row above the keyboard, scrolled sideways so it fits a phone.
enum SymbolBar {
    static let symbols = ["\"", "(", ")", "[", "]", "{", "}", ";", "=", "+", "−", "<", ">", ":", "."]

    static func make(target: Any, action: Selector) -> UIView {
        // An accessory view has to carry its own height: a scroll view has no
        // intrinsic content size, and a zero-height bar would be invisible.
        let container = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        container.autoresizingMask = [.flexibleWidth]
        container.backgroundColor = UIColor(VSCode.titleBar)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.backgroundColor = .clear
        container.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        for symbol in symbols {
            let button = UIButton(type: .system)
            button.setTitle(symbol, for: .normal)
            button.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
            button.setTitleColor(UIColor(VSCode.text), for: .normal)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            button.addTarget(target, action: action, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 34),
        ])

        return container
    }
}

/// Dark+ highlighting for the constructs the interpreter understands.
enum GooseHighlighter {
    static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: VSCode.codeFont,
        .foregroundColor: UIColor(VSCode.text),
    ]

    private static let gooseKeywords: Set<String> = [
        "let", "var", "as", "true", "false", "null", "struct", "enum", "import", "const", "fn"
    ]

    private static let gooseControlKeywords: Set<String> = [
        "if", "else", "while", "for", "in", "return", "break", "continue",
        "match", "recursive", "loop", "block", "guard", "defer",
    ]

    private static let gooseTypes: Set<String> = [
        "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64", "bool", "str",
    ]

    private static func wordSets(
        for language: CodeLanguage
    ) -> (keywords: Set<String>, controls: Set<String>, types: Set<String>) {
        switch language {
        case .goose:
            return (gooseKeywords, gooseControlKeywords, gooseTypes)
        case .c:
            return (
                ["auto", "const", "enum", "extern", "inline", "register", "restrict", "static", "struct", "typedef", "union", "volatile"],
                ["break", "case", "continue", "default", "do", "else", "for", "goto", "if", "return", "switch", "while"],
                ["_Bool", "bool", "char", "double", "FILE", "float", "int", "long", "short", "signed", "size_t", "unsigned", "void"]
            )
        case .assembly:
            return (
                ["bits", "default", "extern", "global", "section", "db", "dw", "dd", "dq", "resb", "resw", "resd", "resq", "equ"],
                ["call", "int", "ja", "jae", "jb", "jbe", "je", "jg", "jge", "jl", "jle", "jmp", "jne", "jnz", "jz", "lea", "mov", "pop", "push", "ret", "syscall", "xor"],
                ["al", "ax", "eax", "rax", "bl", "bx", "ebx", "rbx", "cl", "cx", "ecx", "rcx", "dl", "dx", "edx", "rdx", "rsi", "rdi", "rbp", "rsp", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15"]
            )
        }
    }

    private static func rules(for language: CodeLanguage) -> [(pattern: String, color: UIColor)] {
        let commentPattern = language == .assembly ? #";[^\n]*"# :
            (language == .c ? #"//[^\n]*|/\*[\s\S]*?\*/"# : #"//[^\n]*"#)
        var result: [(pattern: String, color: UIColor)] = [
            (commentPattern, UIColor(VSCode.comment)),
            (#""(?:\\.|[^"\\\n])*""#, UIColor(VSCode.string)),
            (#"\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, UIColor(VSCode.number)),
        ]
        if language == .c {
            result.append((#"(?m)^\s*#\s*[A-Za-z_][A-Za-z0-9_]*"#, UIColor(VSCode.keyword)))
            result.append((#"'(?:\\.|[^'\\\n])*'"#, UIColor(VSCode.string)))
        } else if language == .assembly {
            result.append((#"(?m)^[A-Za-z_.$][A-Za-z0-9_.$]*:"#, UIColor(VSCode.function)))
        }
        return result
    }

    /// Above this the editor stays plain: recolouring a big buffer on every
    /// keystroke is what makes a phone feel slow.
    private static let highlightLimit = 20_000

    private static let compiled: [CodeLanguage: [NSRegularExpression]] = {
        var result: [CodeLanguage: [NSRegularExpression]] = [:]
        for language in CodeLanguage.allCases {
            result[language] = rules(for: language).compactMap {
                try? NSRegularExpression(pattern: $0.pattern)
            }
        }
        return result
    }()

    static func attributed(text: String, language: CodeLanguage = .goose) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes)
        guard text.count <= highlightLimit else { return result }

        let full = NSRange(location: 0, length: (text as NSString).length)
        for (rule, regex) in zip(rules(for: language), compiled[language] ?? []) {
            for match in regex.matches(in: text, range: full) {
                result.addAttributes([.foregroundColor: rule.color], range: match.range)
            }
        }

        colourWords(text, into: result, language: language)
        return result
    }

    /// Recolours only the logical lines touched by an edit; typing does not
    /// rebuild the attributed string for the entire source file.
    static func applyIncremental(
        to storage: NSTextStorage,
        text: NSString,
        changedRange: NSRange,
        language: CodeLanguage = .goose
    ) {
        guard storage.length == text.length else { return }

        let location = min(max(changedRange.location, 0), text.length)
        let replacementEnd = min(max(NSMaxRange(changedRange), location), text.length)
        let previousBreak = text.range(
            of: "\n",
            options: .backwards,
            range: NSRange(location: 0, length: location)
        )
        let lineStart = previousBreak.location == NSNotFound ? 0 : NSMaxRange(previousBreak)
        let nextBreak = text.range(
            of: "\n",
            options: [],
            range: NSRange(location: replacementEnd, length: text.length - replacementEnd)
        )
        let lineEnd = nextBreak.location == NSNotFound ? text.length : NSMaxRange(nextBreak)
        let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
        guard lineRange.length > 0 else { return }

        guard lineRange.length <= highlightLimit else {
            let insertedLength = replacementEnd - location
            if insertedLength > 0 {
                storage.setAttributes(
                    baseAttributes,
                    range: NSRange(location: location, length: insertedLength)
                )
            }
            return
        }

        let line = text.substring(with: lineRange)
        let styledLine = attributed(text: line, language: language)
        storage.beginEditing()
        styledLine.enumerateAttributes(
            in: NSRange(location: 0, length: styledLine.length)
        ) { attributes, range, _ in
            storage.setAttributes(
                attributes,
                range: NSRange(location: lineRange.location + range.location, length: range.length)
            )
        }
        storage.endEditing()
    }

    /// Keywords, types, and the name a `fn` declares.
    private static func colourWords(
        _ text: String,
        into result: NSMutableAttributedString,
        language: CodeLanguage
    ) {
        let nsText = text as NSString
        guard nsText.length > 0 else { return }
        let sets = wordSets(for: language)

        var identifierStart = -1

        func flush(_ end: Int) {
            defer { identifierStart = -1 }
            guard identifierStart >= 0, end > identifierStart else { return }

            let range = NSRange(location: identifierStart, length: end - identifierStart)
            let word = nsText.substring(with: range)

            if sets.controls.contains(word) {
                result.addAttributes(
                    [.foregroundColor: UIColor(VSCode.controlKeyword), .font: VSCode.codeFontBold],
                    range: range
                )
            } else if sets.types.contains(word) {
                result.addAttributes([.foregroundColor: UIColor(VSCode.type)], range: range)
            } else if sets.keywords.contains(word) {
                result.addAttributes(
                    [.foregroundColor: UIColor(VSCode.keyword), .font: VSCode.codeFontBold],
                    range: range
                )
            } else if isDeclaredFunction(before: identifierStart, in: nsText, language: language) {
                result.addAttributes([.foregroundColor: UIColor(VSCode.function)], range: range)
            }
        }

        for index in 0..<nsText.length {
            let character = nsText.character(at: index)
            let isWord = (character >= 48 && character <= 57)
                || (character >= 65 && character <= 90)
                || (character >= 97 && character <= 122)
                || character == 95

            if isWord {
                if identifierStart < 0 { identifierStart = index }
            } else {
                flush(index)
            }
        }
        flush(nsText.length)
    }

    private static func isDeclaredFunction(
        before index: Int,
        in text: NSString,
        language: CodeLanguage
    ) -> Bool {
        var cursor = index - 1
        while cursor >= 0, text.character(at: cursor) == 32 || text.character(at: cursor) == 9 {
            cursor -= 1
        }
        let end = cursor
        while cursor >= 0 {
            let character = text.character(at: cursor)
            let isWord = (character >= 65 && character <= 90) || (character >= 97 && character <= 122)
            if !isWord { break }
            cursor -= 1
        }
        guard end > cursor else { return false }
        let previous = text.substring(with: NSRange(location: cursor + 1, length: end - cursor))
        switch language {
        case .goose:
            return previous == "fn" || previous == "recursive"
        case .c:
            return wordSets(for: .c).types.contains(previous)
        case .assembly:
            return false
        }
    }
}
