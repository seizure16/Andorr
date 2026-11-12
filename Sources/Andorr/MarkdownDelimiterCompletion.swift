import AppKit
import AndorrCore

/// Tracks only delimiters inserted by this editor, so manually written Markdown
/// and pasted text are never mistaken for automatically inserted closers.
@MainActor
final class MarkdownDelimiterCompletion {
    struct Pair: Equatable {
        var opening: Int
        var closing: Int
        var delimiter: String
        var width: Int { delimiter.utf16.count }
        var openingRange: NSRange { NSRange(location: opening, length: width) }
        var closingRange: NSRange { NSRange(location: closing, length: width) }
        var contentRange: NSRange { NSRange(location: opening + width, length: closing - opening - width) }
    }

    private weak var view: MarkdownTextView?
    private var pairs: [Pair] = []
    private var makingPairedEdit = false

    init(view: MarkdownTextView) { self.view = view }
    func reset() { pairs = [] }

    func insert(_ input: String, replacementRange: NSRange) -> Bool {
        guard let view, view.automaticallyCloseMarkdown, view.isEditable, !view.hasMarkedText() else { return false }
        let selection = replacementRange.location == NSNotFound ? view.selectedRange() : replacementRange
        let text = view.string as NSString
        guard NSMaxRange(selection) <= text.length else { return false }

        // Typing a space after a single empty '*' keeps Markdown list entry easy.
        if input == " ", let pair = pairs.last(where: { $0.width == 1 && $0.contentRange == selection && selection.length == 0 }) {
            guard !isCode(at: selection, text: text) else { return false }
            return replace(NSRange(location: pair.opening, length: 2), with: pair.delimiter + input,
                           selection: NSRange(location: pair.opening + 2, length: 0))
        }
        guard input == "*" || input == "_", !isCode(at: selection, text: text) else { return false }

        // The second '*' upgrades the automatically inserted italic pair to bold.
        if let pair = pairs.last(where: { $0.delimiter == input && $0.contentRange == selection }) {
            let body = text.substring(with: selection)
            let delimiter = input + input
            return replace(NSRange(location: pair.opening, length: pair.closing + pair.width - pair.opening),
                           with: delimiter + body + delimiter,
                           selection: NSRange(location: pair.opening + 2, length: selection.length),
                           pair: Pair(opening: pair.opening, closing: pair.opening + 2 + selection.length, delimiter: delimiter))
        }
        if selection.length == 0, pairs.contains(where: {
            NSLocationInRange(selection.location, $0.closingRange) && text.substring(with: NSRange(location: selection.location, length: 1)) == input
        }) {
            view.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
            return true
        }
        guard canOpen(at: selection, input: input, text: text) else { return false }
        let body = text.substring(with: selection)
        return replace(selection, with: input + body + input,
                       selection: NSRange(location: selection.location + 1, length: selection.length),
                       pair: Pair(opening: selection.location, closing: selection.location + 1 + selection.length, delimiter: input))
    }

    func deleteBackward() -> Bool {
        guard let view, view.automaticallyCloseMarkdown, view.isEditable, !view.hasMarkedText() else { return false }
        let caret = view.selectedRange()
        guard caret.length == 0, let pair = pairs.last(where: { $0.contentRange == caret }),
              !isCode(at: caret, text: view.string as NSString) else { return false }
        return replace(NSRange(location: pair.opening, length: pair.width * 2), with: "",
                       selection: NSRange(location: pair.opening, length: 0))
    }

    /// Called only after AppKit/delegates accept a native replacement.
    func textWillChange(in range: NSRange, replacement: String) {
        let before = pairs
        let delta = (replacement as NSString).length - range.length
        pairs = pairs.compactMap { original in
            var pair = original
            if range.length > 0 && (NSIntersectionRange(range, pair.openingRange).length > 0 || NSIntersectionRange(range, pair.closingRange).length > 0) { return nil }
            if range.length == 0 && ((range.location > pair.opening && range.location < pair.opening + pair.width) ||
                                    (range.location > pair.closing && range.location < pair.closing + pair.width)) { return nil }
            if NSMaxRange(range) <= pair.opening { pair.opening += delta }
            if NSMaxRange(range) <= pair.closing { pair.closing += delta }
            return pair
        }
        if !makingPairedEdit, before != pairs { registerRestoration(before) }
    }

    private func canOpen(at range: NSRange, input: String, text: NSString) -> Bool {
        var slashes = 0, previous = range.location
        while previous > 0, text.character(at: previous - 1) == 92 { slashes += 1; previous -= 1 }
        guard slashes % 2 == 0 else { return false }
        let alphanumerics = CharacterSet.alphanumerics as NSCharacterSet
        if range.length == 0 {
            // Don't insert pairs in identifiers or in the middle of existing text.
            if range.location < text.length, alphanumerics.characterIsMember(text.character(at: range.location)) { return false }
            if input == "_", range.location > 0, alphanumerics.characterIsMember(text.character(at: range.location - 1)) { return false }
        }
        return true
    }

    private func isCode(at range: NSRange, text: NSString) -> Bool {
        let syntax = MarkdownEditorSyntax.spans(in: text as String)
        return syntax.contains { span in
            switch span.style {
            case .codeBlock:
                if range.length > 0 { return NSIntersectionRange(range, span.range).length > 0 }
                if range.location >= span.range.location && range.location <= NSMaxRange(span.range) { return true }
                // CommonMark omits trailing empty lines from an unfinished fence.
                // The caret after its final newline is still inside that block.
                if range.location > NSMaxRange(span.range) {
                    let gap = NSRange(location: NSMaxRange(span.range), length: range.location - NSMaxRange(span.range))
                    let fences = syntax.filter { $0.style == .marker && NSIntersectionRange($0.range, span.range).length > 0 }
                    return fences.count == 1 && text.substring(with: gap).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return false
            case .code:
                return range.length > 0 ? NSIntersectionRange(range, span.range).length > 0 :
                    range.location > span.range.location && range.location < NSMaxRange(span.range)
            default: return false
            }
        }
    }

    private func replace(_ range: NSRange, with text: String, selection: NSRange, pair: Pair? = nil) -> Bool {
        guard let view else { return false }
        let before = pairs
        let oldText = view.string
        view.breakUndoCoalescing()
        view.undoManager?.beginUndoGrouping()
        makingPairedEdit = true
        view.insertLiteralText(text, replacementRange: range)
        makingPairedEdit = false
        if view.string != oldText {
            if let pair { pairs.append(pair) }
            view.setSelectedRange(selection)
            registerRestoration(before)
        }
        view.breakUndoCoalescing()
        view.undoManager?.endUndoGrouping()
        return view.string != oldText
    }

    private func registerRestoration(_ snapshot: [Pair]) {
        view?.undoManager?.registerUndo(withTarget: self) { completion in
            let current = completion.pairs
            completion.pairs = snapshot
            completion.registerRestoration(current)
        }
    }
}
