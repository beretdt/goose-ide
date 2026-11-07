import Foundation

/// Finds the ```goose block in a reply that may still be arriving.
///
/// The chat asks the model to answer with the whole file in one block, so the
/// editor can show the change while the answer is still streaming. Until the
/// closing fence arrives the block is open, and half a file is still worth
/// showing — it is the same file being rewritten line by line.
public enum AIEditExtractor {
    public static let openingFence = "```goose"
    public static let fence = "```"

    /// The code inside the first ```goose block, or nil when no block started.
    /// `closed` tells whether the closing fence already arrived.
    public static func gooseBlock(in text: String) -> (code: String, closed: Bool)? {
        guard let opening = text.range(of: openingFence) else { return nil }

        let rest = text[opening.upperBound...]
        // The fence may sit on the same line as the first code line.
        let afterFence = rest.hasPrefix("\n") ? rest.dropFirst() : rest.drop(while: { $0 == " " })

        if let closing = afterFence.range(of: fence) {
            return (String(afterFence[..<closing.lowerBound]), true)
        }
        return (String(afterFence), false)
    }

    /// The reply without the code block, for the chat bubble.
    public static func prose(in text: String) -> String {
        var result = text
        while let opening = result.range(of: openingFence) {
            let rest = result[opening.lowerBound...]
            guard let closing = rest.range(of: fence, range: rest.index(after: rest.startIndex)..<rest.endIndex) else {
                result = String(result[..<opening.lowerBound])
                break
            }
            result.replaceSubrange(opening.lowerBound..<closing.upperBound, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
