import XCTest
@testable import AndorrCore

final class MarkdownEditorSyntaxTests: XCTestCase {
    func testUnicodeAndCRLFSourceRangesMatchMarkdownTokens() {
        let source = "# Révision 🧠\r\n\r\nÉté 😀 **important** et *utile*, `x < y`.\r\n"
        let text = source as NSString
        let spans = MarkdownEditorSyntax.spans(in: source)
        func tokens(_ style: MarkdownEditorSpan.Style) -> [String] {
            spans.filter { $0.style == style }.map { text.substring(with: $0.range) }
        }
        XCTAssertEqual(tokens(.heading(1)), ["# Révision 🧠"])
        XCTAssertEqual(tokens(.strong), ["**important**"])
        XCTAssertEqual(tokens(.emphasis), ["*utile*"])
        XCTAssertEqual(tokens(.code), ["`x < y`"])
        for span in spans {
            XCTAssertGreaterThanOrEqual(span.range.location, 0)
            XCTAssertLessThanOrEqual(NSMaxRange(span.range), text.length)
        }
    }

    func testCodeAndEscapedMarkdownDoNotBecomeEmphasis() {
        let source = "\\*literal\\*\n\n```swift\n**not bold**\n```\n\n[Un lien](https://example.com)\n"
        let spans = MarkdownEditorSyntax.spans(in: source)
        XCTAssertFalse(spans.contains { $0.style == .strong || $0.style == .emphasis })
        XCTAssertTrue(spans.contains { $0.style == .codeBlock })
        XCTAssertTrue(spans.contains { $0.style == .link })
    }

    func testNestedFormattingAndIncompleteMarkdown() {
        let spans = MarkdownEditorSyntax.spans(in: "**gras et *italique***\n\n**inachevé\n")
        XCTAssertEqual(spans.filter { $0.style == .strong }.count, 1)
        XCTAssertEqual(spans.filter { $0.style == .emphasis }.count, 1)
        XCTAssertTrue(MarkdownEditorSyntax.spans(in: "").isEmpty)
    }
    func testUnchangedDocumentNeedsNoRestyling() {
        let source = "# Révision\n\n**Cours** 😀"
        let spans = MarkdownEditorSyntax.spans(in: source)
        XCTAssertNil(MarkdownEditorSyntax.changedRange(from: source, spans: spans, to: source, spans: spans))
    }

    func testLocalEditKeepsDistantUnchangedStylesOutsideDirtyRange() throws {
        let old = "Un **cours**.\n\n" + String(repeating: "# Titre\n\n", count: 1000)
        let new = old.replacingOccurrences(of: "cours", with: "cours 😀 et révision")
        let dirty = try XCTUnwrap(MarkdownEditorSyntax.changedRange(from: old, spans: MarkdownEditorSyntax.spans(in: old),
                                                                  to: new, spans: MarkdownEditorSyntax.spans(in: new)))
        XCTAssertEqual(dirty.location, 0)
        XCTAssertLessThan(dirty.length, 100)
    }

    func testSyntaxChangeCanInvalidateEarlierParagraphs() throws {
        let old = "[Cours][reference]\n\nDu texte.\n\n"
        let new = old + "[reference]: https://example.com\n"
        let dirty = try XCTUnwrap(MarkdownEditorSyntax.changedRange(from: old, spans: MarkdownEditorSyntax.spans(in: old),
                                                                  to: new, spans: MarkdownEditorSyntax.spans(in: new)))
        XCTAssertEqual(dirty.location, 0)
        XCTAssertGreaterThan(dirty.length, (old as NSString).length)
    }

    func testCodeSpansAndFencesKeepLiteralContentsAndFindTheirDelimiters() {
        for (source, expectedStyle, delimiters) in [
            ("Du ```code``` en ligne", MarkdownEditorSpan.Style.code, ["```", "```"]),
            ("```swift\r\nlet value = \"**littéral**\"\r\n```\r\n", .codeBlock, ["```swift", "```"]),
            ("~~~~python\nprint('`code`')\n~~~~~", .codeBlock, ["~~~~python", "~~~~~"]),
            ("    **littéral**\n    `code`\n", .codeBlock, [])
        ] {
            let spans = MarkdownEditorSyntax.spans(in: source)
            XCTAssertTrue(spans.contains { $0.style == expectedStyle }, source)
            XCTAssertFalse(spans.contains { $0.style == .strong || $0.style == .emphasis })
            let tokens = spans.filter { $0.style == .marker }.map { (source as NSString).substring(with: $0.range) }
            XCTAssertEqual(tokens, delimiters, source)
        }
    }

    func testUnfinishedAndLongerFencesRemainEditable() {
        for source in ["```", "```swift\nlet value = 1", "````\n```\nbody"] {
            let spans = MarkdownEditorSyntax.spans(in: source)
            XCTAssertTrue(spans.contains { $0.style == .codeBlock })
            let markers = spans.filter { $0.style == .marker }
            XCTAssertEqual(markers.count, 1)
            XCTAssertEqual(markers.first?.revealRange, markers.first?.range)
            XCTAssertEqual(markers.first?.revealAtEnd, true)
        }
    }

    func testWhitespaceBeforeCloserProducesOnlyEditingFallbackForThatPair() throws {
        for delimiter in ["**", "__", "*", "_"] {
            let source = "**valide** puis " + delimiter + "Bonjour  " + delimiter
            let spans = MarkdownEditorSyntax.spans(in: source)
            let provisional = spans.filter(\.provisional)
            XCTAssertEqual(provisional.count, 1)
            let span = try XCTUnwrap(provisional.first)
            XCTAssertEqual(span.style, delimiter.count == 2 ? .strong : .emphasis)
            XCTAssertEqual((source as NSString).substring(with: span.range), delimiter + "Bonjour  " + delimiter)
            XCTAssertEqual(span.revealRange, NSRange(location: 0, length: (source as NSString).length))
            XCTAssertTrue(spans.contains { !$0.provisional && $0.style == .strong })
        }
    }

    func testEditingFallbackDoesNotInterpretLiteralOrEscapedDelimiters() {
        for source in ["`**Bonjour **`", "```\n**Bonjour **\n```", "<pre>\n**Bonjour **\n</pre>",
                       "\\**Bonjour **", "mot__Bonjour __", "**  **", "**Bonjour**", "**inachevé"] {
            XCTAssertFalse(MarkdownEditorSyntax.spans(in: source).contains(where: \.provisional), source)
        }
    }

}
