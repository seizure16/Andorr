import AppKit
import AndorrCore
import Highlightr

struct MarkdownCodeColor: Equatable {
    let range: NSRange
    let color: NSColor
}

/// Owns JavaScriptCore away from the UI, with serialized access and a bounded
/// cache so edits to prose do not highlight unchanged code again.
actor MarkdownCodeHighlighter {
    private struct Key: Hashable {
        let code: String
        let language: String
        let dark: Bool
    }

    private lazy var engine = Highlightr()
    private var cache: [Key: [MarkdownCodeColor]] = [:]
    private let aliases = ["sh": "bash", "shell": "bash", "zsh": "bash", "js": "javascript",
                           "ts": "typescript", "py": "python", "html": "xml", "yml": "yaml",
                           "c++": "cpp", "c#": "csharp", "cs": "csharp", "objc": "objectivec", "md": "markdown"]

    func colors(in source: String, spans: [MarkdownEditorSpan], dark: Bool) -> [MarkdownCodeColor] {
        guard let engine else { return [] }
        let supported = Set(engine.supportedLanguages())
        let text = source as NSString
        var colors: [MarkdownCodeColor] = []
        for block in spans where block.style == .codeBlock {
            guard !Task.isCancelled, NSMaxRange(block.range) <= text.length else { break }
            let token = text.substring(with: block.range) as NSString
            var firstEnd = 0, contentStart = 0
            token.getLineStart(nil, end: &contentStart, contentsEnd: &firstEnd, for: NSRange(location: 0, length: 0))
            let opening = token.substring(to: firstEnd).trimmingCharacters(in: .whitespaces)
            guard let fence = opening.first, fence == "`" || fence == "~" else { continue }
            let width = opening.prefix(while: { $0 == fence }).count
            guard width >= 3,
                  let info = opening.dropFirst(width).split(whereSeparator: { $0.isWhitespace }).first else { continue }
            let name = info.lowercased()
            let language = aliases[name] ?? name
            guard supported.contains(language) else { continue }
            let start = block.range.location + contentStart
            let closing = spans.first {
                $0.style == .marker && $0.range.location >= start &&
                    $0.range.location < NSMaxRange(block.range)
            }
            let end = closing?.range.location ?? NSMaxRange(block.range)
            guard end > start, end - start <= 50_000 else { continue }
            let code = text.substring(with: NSRange(location: start, length: end - start))
            let key = Key(code: code, language: language, dark: dark)
            let local: [MarkdownCodeColor]
            if let cached = cache[key] { local = cached }
            else {
                // Highlightr's CSS reader cannot parse compound selectors such
                // as `.hljs-title.class_` in Atom One: the whole rule, including
                // Bash builtins, is lost. These themes use compatible selectors.
                guard engine.setTheme(to: dark ? "vs2015" : "vs") else { continue }
                engine.ignoreIllegals = true
                guard let highlighted = engine.highlight(code, as: language), highlighted.string == code else { continue }
                var result: [MarkdownCodeColor] = []
                highlighted.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: highlighted.length)) { value, range, _ in
                    if let color = value as? NSColor { result.append(MarkdownCodeColor(range: range, color: color)) }
                }
                local = result
                if cache.count >= 64 { cache.removeAll(keepingCapacity: true) }
                cache[key] = local
            }
            colors += local.map { MarkdownCodeColor(range: NSRange(location: start + $0.range.location, length: $0.range.length), color: $0.color) }
        }
        return colors
    }
}
