import Foundation
import Markdown

/// Source ranges are UTF-16 for AppKit; parsing itself uses CommonMark's UTF-8 columns.
public struct MarkdownEditorSpan: Hashable, Sendable {
    public enum Style: Hashable, Sendable {
        case heading(Int), strong, emphasis, code, codeBlock, quote, link, marker
    }
    public let range: NSRange
    public let style: Style
    public let revealRange: NSRange?
    public let revealAtEnd: Bool
}

public enum MarkdownEditorSyntax {
    /// Native text storage already shifts existing attributes with character edits.
    /// Repaint changed paragraphs plus any syntax whose meaning changed elsewhere
    /// (for example a reference link or a newly closed multiline code fence).
    public static func changedRange(from oldSource: String, spans oldSpans: [MarkdownEditorSpan],
                                    to source: String, spans: [MarkdownEditorSpan]) -> NSRange? {
        let old = Array(oldSource.utf16), new = Array(source.utf16)
        var start = 0
        while start < min(old.count, new.count), old[start] == new[start] { start += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - start,
              old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
        let oldEnd = old.count - suffix, newEnd = new.count - suffix
        let delta = new.count - old.count
        func mapped(_ range: NSRange) -> NSRange {
            let first = range.location < start ? range.location : range.location >= oldEnd ? range.location + delta : start
            let end = NSMaxRange(range) <= start ? NSMaxRange(range) : NSMaxRange(range) >= oldEnd ? NSMaxRange(range) + delta : newEnd
            let clippedStart = max(0, min(first, new.count))
            return NSRange(location: clippedStart, length: max(0, min(end, new.count) - clippedStart))
        }
        let previous = Set(oldSpans.map {
            MarkdownEditorSpan(range: mapped($0.range), style: $0.style,
                               revealRange: $0.revealRange.map(mapped), revealAtEnd: $0.revealAtEnd)
        })
        let current = Set(spans)
        var dirty: NSRange? = oldSource == source ? nil : NSRange(location: start, length: newEnd - start)
        for span in previous.symmetricDifference(current) {
            dirty = dirty.map { NSUnionRange($0, span.range) } ?? span.range
        }
        guard let dirty else { return nil }
        return (source as NSString).paragraphRange(for: dirty)
    }

    public static func spans(in source: String) -> [MarkdownEditorSpan] {
        let bytes = Array(source.utf8)
        var lineStarts = [0]
        for (index, byte) in bytes.enumerated() where byte == 10 { lineStarts.append(index + 1) }
        func offset(_ location: SourceLocation) -> Int? {
            guard location.line > 0, location.line <= lineStarts.count, location.column > 0 else { return nil }
            let start = lineStarts[location.line - 1]
            let end = location.line < lineStarts.count ? lineStarts[location.line] : bytes.count
            let position = start + location.column - 1
            guard position <= end else { return nil }
            return position
        }
        // Build the byte -> UTF-16 map once, rather than scanning the document per node.
        var utf16Offsets = [Int](repeating: 0, count: bytes.count + 1)
        var byteOffset = 0
        var utf16Offset = 0
        for scalar in source.unicodeScalars {
            for index in 0..<scalar.utf8.count { utf16Offsets[byteOffset + index] = utf16Offset }
            byteOffset += scalar.utf8.count
            utf16Offset += scalar.utf16.count
        }
        utf16Offsets[bytes.count] = utf16Offset
        func range(_ node: any Markup) -> NSRange? {
            guard let location = node.range, let start = offset(location.lowerBound),
                  let end = offset(location.upperBound), end >= start else { return nil }
            return NSRange(location: utf16Offsets[start], length: utf16Offsets[end] - utf16Offsets[start])
        }
        let text = source as NSString
        var spans: [MarkdownEditorSpan] = []
        func append(_ range: NSRange, _ style: MarkdownEditorSpan.Style, revealRange: NSRange? = nil, revealAtEnd: Bool = false) {
            guard range.length > 0, NSMaxRange(range) <= text.length else { return }
            spans.append(.init(range: range, style: style, revealRange: revealRange, revealAtEnd: revealAtEnd))
        }
        func visit(_ node: any Markup) {
            guard let nodeRange = range(node) else {
                for child in node.children { visit(child) }; return
            }
            var delimiters = false
            switch node {
            case let heading as Heading: append(nodeRange, .heading(heading.level)); delimiters = true
            case is Strong: append(nodeRange, .strong); delimiters = true
            case is Emphasis: append(nodeRange, .emphasis); delimiters = true
            case is Link: append(nodeRange, .link); delimiters = true
            case is InlineCode:
                append(nodeRange, .code)
                let token = text.substring(with: nodeRange)
                let ticks = token.prefix { $0 == "`" }.count
                if ticks > 0, nodeRange.length >= ticks * 2 {
                    append(NSRange(location: nodeRange.location, length: ticks), .marker, revealRange: nodeRange)
                    append(NSRange(location: NSMaxRange(nodeRange) - ticks, length: ticks), .marker, revealRange: nodeRange)
                }
            case is CodeBlock:
                append(nodeRange, .codeBlock)
                let token = text.substring(with: nodeRange).trimmingCharacters(in: .newlines) as NSString
                var firstEnd = 0
                token.getLineStart(nil, end: nil, contentsEnd: &firstEnd, for: NSRange(location: 0, length: 0))
                let firstLine = token.substring(to: firstEnd)
                let opening = firstLine.drop(while: { $0 == " " || $0 == "\t" })
                if let fence = opening.first, fence == "`" || fence == "~" {
                    let count = opening.prefix(while: { $0 == fence }).count
                    if count >= 3 {
                        let firstRange = NSRange(location: nodeRange.location, length: firstEnd)
                        append(firstRange, .marker, revealRange: firstRange, revealAtEnd: true)
                        var lastStart = 0, lastEnd = 0
                        token.getLineStart(&lastStart, end: nil, contentsEnd: &lastEnd,
                                           for: NSRange(location: max(0, token.length - 1), length: 0))
                        let closing = token.substring(with: NSRange(location: lastStart, length: lastEnd - lastStart))
                            .trimmingCharacters(in: .whitespaces)
                        if lastStart > 0, closing.count >= count, closing.allSatisfy({ $0 == fence }) {
                            let lastRange = NSRange(location: nodeRange.location + lastStart, length: lastEnd - lastStart)
                            append(lastRange, .marker, revealRange: lastRange, revealAtEnd: true)
                        }
                    }
                }
            case is BlockQuote: append(nodeRange, .quote)
            default: break
            }
            if delimiters, let first = node.child(at: 0), let last = node.child(at: node.childCount - 1),
               let firstRange = range(first), let lastRange = range(last),
               firstRange.location >= nodeRange.location, NSMaxRange(lastRange) <= NSMaxRange(nodeRange) {
                append(NSRange(location: nodeRange.location, length: firstRange.location - nodeRange.location), .marker, revealRange: nodeRange, revealAtEnd: node is Heading)
                append(NSRange(location: NSMaxRange(lastRange), length: NSMaxRange(nodeRange) - NSMaxRange(lastRange)), .marker, revealRange: nodeRange, revealAtEnd: node is Heading)
            }
            for child in node.children { visit(child) }
        }
        visit(Document(parsing: source))
        return spans
    }
}
