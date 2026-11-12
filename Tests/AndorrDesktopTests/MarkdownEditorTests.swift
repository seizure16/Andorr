import AppKit
import XCTest
import AndorrCore
@testable import AndorrDesktop

final class MarkdownEditorTests: XCTestCase {
    @MainActor
    func testFormattingPreservesTextSelectionAndDoesNotWriteToBinding() {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view
        view.delegate = coordinator
        let source = "# Titre\n\n**Gras** et *italique* 😀\n"
        var writes: [String] = []
        coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: false) { writes.append($0) }
        coordinator.parseTask?.cancel()
        coordinator.spans = MarkdownEditorSyntax.spans(in: source)
        coordinator.styledSource = source
        view.setSelectedRange(NSRange(location: 12, length: 3))
        coordinator.render()
        XCTAssertEqual(view.string, source)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 12, length: 3))
        XCTAssertTrue(writes.isEmpty)
        let headingFont = view.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        XCTAssertEqual(headingFont?.pointSize, 28)
        coordinator.update(text: source, noteID: "A", zoom: 1.5, live: true, editable: true, dark: true) { writes.append($0) }
        coordinator.parseTask?.cancel()
        XCTAssertEqual(view.selectedRange(), NSRange(location: 12, length: 3))
        XCTAssertEqual(view.string, source)
        XCTAssertTrue(writes.isEmpty)
    }

    @MainActor
    func testTypingAndUndoStillDeliverRawMarkdownAndNoteSwitchClearsUndo() {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.isRichText = false
        view.allowsUndo = true
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view
        view.delegate = coordinator
        var body = ""
        coordinator.update(text: "", noteID: "A", zoom: 1, live: true, editable: true, dark: false) { body = $0 }
        view.undoManager?.groupsByEvent = false
        view.undoManager?.beginUndoGrouping()
        view.insertText("**Révision 😀**", replacementRange: view.selectedRange())
        view.breakUndoCoalescing()
        view.undoManager?.endUndoGrouping()
        XCTAssertEqual(body, "**Révision 😀**")
        coordinator.parseTask?.cancel()
        coordinator.spans = MarkdownEditorSyntax.spans(in: body)
        coordinator.styledSource = body
        coordinator.render()
        XCTAssertTrue(view.tryToPerform(#selector(MarkdownTextView.undo(_:)), with: nil))
        XCTAssertEqual(body, "")
        XCTAssertEqual(view.string, "")
        XCTAssertTrue(view.tryToPerform(#selector(MarkdownTextView.redo(_:)), with: nil))
        XCTAssertEqual(body, "**Révision 😀**")
        coordinator.update(text: "Other note", noteID: "B", zoom: 1, live: false, editable: true, dark: false) { body = $0 }
        coordinator.parseTask?.cancel()
        XCTAssertEqual(view.string, "Other note")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertFalse(view.undoManager?.canUndo ?? true)
        XCTAssertFalse(view.undoManager?.canRedo ?? true)
        XCTAssertEqual(body, "**Révision 😀**")
    }
    @MainActor
    func testStaleBackgroundParsingCannotStyleAnotherNote() async throws {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view
        view.delegate = coordinator
        coordinator.update(text: "# First", noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
        coordinator.update(text: "Plain text 😀", noteID: "B", zoom: 1, live: true, editable: true, dark: false) { _ in }
        await coordinator.parseTask?.value
        XCTAssertEqual(view.string, "Plain text 😀")
        XCTAssertEqual(coordinator.styledSource, view.string)
        XCTAssertTrue(coordinator.spans.isEmpty)
        XCTAssertEqual((view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 15)
    }

    @MainActor
    func testMarkersReactToCursorWithoutChangingSource() {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view
        view.delegate = coordinator
        let source = "**Important**\n\nAutre paragraphe"
        coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
        coordinator.parseTask?.cancel()
        coordinator.spans = MarkdownEditorSyntax.spans(in: source)
        coordinator.styledSource = source
        coordinator.editorFocused = true
        view.setSelectedRange(NSRange(location: 3, length: 0))
        coordinator.render()
        let activeHidden = view.textStorage?.attribute(.markdownConcealed, at: 0, effectiveRange: nil) as? Bool
        view.setSelectedRange(NSRange(location: 20, length: 0))
        coordinator.render()
        let inactiveHidden = view.textStorage?.attribute(.markdownConcealed, at: 0, effectiveRange: nil) as? Bool
        XCTAssertNil(activeHidden)
        XCTAssertEqual(inactiveHidden, true)
        let layout = view.layoutManager!
        layout.ensureLayout(for: view.textContainer!)
        let glyph = layout.glyphIndexForCharacter(at: 0)
        XCTAssertTrue(layout.propertyForGlyph(at: glyph).contains(.null))
        let firstVisibleGlyph = layout.glyphIndexForCharacter(at: 2)
        XCTAssertFalse(layout.propertyForGlyph(at: firstVisibleGlyph).contains(.null))
        // Hidden syntax occupies no horizontal space before the visible word.
        XCTAssertEqual(layout.location(forGlyphAt: glyph).x, layout.location(forGlyphAt: firstVisibleGlyph).x, accuracy: 0.1)
        coordinator.editorFocused = false
        coordinator.render()
        XCTAssertEqual(view.textStorage?.attribute(.markdownConcealed, at: 0, effectiveRange: nil) as? Bool, true)
        coordinator.update(text: source, noteID: "A", zoom: 1, live: false, editable: true, dark: false) { _ in }
        layout.ensureLayout(for: view.textContainer!)
        XCTAssertFalse(layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: 0)).contains(.null))
        XCTAssertEqual(view.string, source)
    }

    @MainActor
    func testConcealedTitlesAndInlineSyntaxRetainOriginalMarkdown() throws {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.isRichText = false
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view
        view.delegate = coordinator
        let source = "# Titre 😀\n\nDu **gras** et `code` avec [lien](https://example.com).\n"
        coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
        coordinator.parseTask?.cancel()
        coordinator.spans = MarkdownEditorSyntax.spans(in: source)
        coordinator.styledSource = source
        coordinator.render()
        let layout = try XCTUnwrap(view.layoutManager)
        layout.ensureLayout(for: try XCTUnwrap(view.textContainer))
        let markers = coordinator.spans.filter { $0.style == .marker }
        XCTAssertEqual(markers.count, 7)
        for marker in markers {
            for character in marker.range.location..<NSMaxRange(marker.range) {
                XCTAssertTrue(layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: character)).contains(.null))
            }
        }
        view.setSelectedRange(NSRange(location: 0, length: (source as NSString).length))
        XCTAssertEqual(view.selectedRange().length, (source as NSString).length)
        XCTAssertEqual(view.string, source)
        coordinator.editorFocused = true
        view.setSelectedRange(NSRange(location: 5, length: 0))
        coordinator.render()
        layout.ensureLayout(for: view.textContainer!)
        XCTAssertFalse(layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: 0)).contains(.null))
        let boldMarker = (source as NSString).range(of: "**").location
        XCTAssertTrue(layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: boldMarker)).contains(.null))
        XCTAssertEqual(view.string, source)
    }

    @MainActor
    func testInlineSyntaxHidesWhenCaretLeavesTheCompletedElement() async {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.isRichText = false
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
        var saved = ""
        coordinator.update(text: "", noteID: "A", zoom: 1, live: true, editable: true, dark: false) { saved = $0 }
        for character in "**gras**" { view.insertText(String(character), replacementRange: view.selectedRange()) }
        await coordinator.parseTask?.value
        XCTAssertEqual(saved, "**gras**")
        XCTAssertEqual(view.selectedRange().location, 8)
        XCTAssertEqual(view.textStorage?.attribute(.markdownConcealed, at: 0, effectiveRange: nil) as? Bool, true)
        view.moveLeft(nil)
        XCTAssertGreaterThanOrEqual(view.selectedRange().location, 2)
        XCTAssertLessThan(view.selectedRange().location, 6)
        XCTAssertNil(view.textStorage?.attribute(.markdownConcealed, at: 0, effectiveRange: nil))
        view.moveToEndOfLine(nil)
        XCTAssertEqual(view.textStorage?.attribute(.markdownConcealed, at: 0, effectiveRange: nil) as? Bool, true)
        for character in " puis *italique* et `code`" { view.insertText(String(character), replacementRange: view.selectedRange()) }
        await coordinator.parseTask?.value
        XCTAssertEqual(saved, "**gras** puis *italique* et `code`")
        XCTAssertEqual(coordinator.styledSource, saved)
        for marker in coordinator.spans where marker.style == .marker {
            XCTAssertEqual(view.textStorage?.attribute(.markdownConcealed, at: marker.range.location, effectiveRange: nil) as? Bool, true)
        }
        XCTAssertFalse(NSFontManager.shared.traits(of: view.typingAttributes[.font] as! NSFont).contains(.boldFontMask))
        view.insertText("\n", replacementRange: view.selectedRange())
        await coordinator.parseTask?.value
        for marker in coordinator.spans where marker.style == .marker {
            XCTAssertEqual(view.textStorage?.attribute(.markdownConcealed, at: marker.range.location, effectiveRange: nil) as? Bool, true)
        }
    }

    @MainActor
    func testOnlyEditedElementRevealsItsMarkersWithinTheSameLine() async {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
        let source = "**premier** puis **second** et fin\nAutre ligne"
        coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
        await coordinator.parseTask?.value
        let second = (source as NSString).range(of: "**second**").location
        view.setSelectedRange(NSRange(location: 3, length: 0))
        XCTAssertNil(view.textStorage?.attribute(.markdownConcealed, at: 0, effectiveRange: nil))
        XCTAssertEqual(view.textStorage?.attribute(.markdownConcealed, at: second, effectiveRange: nil) as? Bool, true)
        view.setSelectedRange(NSRange(location: second + 3, length: 0))
        XCTAssertEqual(view.textStorage?.attribute(.markdownConcealed, at: 0, effectiveRange: nil) as? Bool, true)
        XCTAssertNil(view.textStorage?.attribute(.markdownConcealed, at: second, effectiveRange: nil))
        view.setSelectedRange(NSRange(location: 2, length: second + 4))
        let selection = view.selectedRange()
        XCTAssertNil(view.textStorage?.attribute(.markdownConcealed, at: 0, effectiveRange: nil))
        XCTAssertNil(view.textStorage?.attribute(.markdownConcealed, at: second, effectiveRange: nil))
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(view.string, source)
        view.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        for marker in coordinator.spans where marker.style == .marker {
            XCTAssertEqual(view.textStorage?.attribute(.markdownConcealed, at: marker.range.location, effectiveRange: nil) as? Bool, true)
        }
    }

    @MainActor
    func testCompositionIsNotRestyledOrRepositioned() async {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
        coordinator.update(text: "**cours** ", noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
        await coordinator.parseTask?.value
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.setMarkedText("é", selectedRange: NSRange(location: 1, length: 0), replacementRange: view.selectedRange())
        XCTAssertTrue(view.hasMarkedText())
        let before = NSAttributedString(attributedString: view.textStorage!)
        let selection = view.selectedRange()
        coordinator.render(); coordinator.updateConcealment()
        XCTAssertEqual(view.textStorage, before)
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertTrue(view.hasMarkedText())
        view.unmarkText()
        coordinator.scheduleParse()
        await coordinator.parseTask?.value
        XCTAssertEqual(coordinator.styledSource, view.string)
        XCTAssertEqual(view.string, "**cours** é")
    }

    @MainActor
    func testRenderingPreservesScrollAndSelectionInLongDocument() async {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.maxSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
        let source = String(repeating: "Cours **important** avec *italique* et du texte.\n\n", count: 500)
        coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
        await coordinator.parseTask?.value
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        view.sizeToFit()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
        let origin = scroll.contentView.bounds.origin
        let caret = (source as NSString).range(of: "important").location + 3
        view.setSelectedRange(NSRange(location: caret, length: 0))
        coordinator.updateConcealment()
        XCTAssertEqual(view.selectedRange(), NSRange(location: caret, length: 0))
        XCTAssertEqual(scroll.contentView.bounds.origin, origin)
        coordinator.render()
        XCTAssertEqual(scroll.contentView.bounds.origin, origin)
        XCTAssertEqual(view.string, source)
    }

    @MainActor
    func testSelectionChangesOnlyInvalidateLocalMarkersInLongDocument() async {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
        let source = String(repeating: "Un **cours** avec du texte.\n\n", count: 1000)
        coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
        await coordinator.parseTask?.value
        view.setSelectedRange(NSRange(location: (source as NSString).range(of: "\n").location + 1, length: 0))
        let recorder = EditorStorageRecorder()
        view.textStorage?.delegate = recorder
        view.setSelectedRange(NSRange(location: 7, length: 0))
        XCTAssertFalse(recorder.editedRanges.isEmpty)
        XCTAssertTrue(recorder.editedRanges.allSatisfy { NSMaxRange($0) < (source as NSString).length / 100 })
        recorder.editedRanges = []
        // Moving inside the same span doesn't touch any stored attributes.
        view.setSelectedRange(NSRange(location: 8, length: 0))
        XCTAssertTrue(recorder.editedRanges.isEmpty)
        // An unchanged parse result also leaves storage untouched.
        coordinator.render()
        XCTAssertTrue(recorder.editedRanges.isEmpty)
        XCTAssertEqual(view.string, source)
    }

    @MainActor
    func testIncrementalRenderingMatchesFreshRenderingAfterEditsAndPaste() async throws {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.isRichText = false
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
        coordinator.update(text: "# Titre\n\nUn **gras** et du `code`.\n\nFin", noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
        await coordinator.parseTask?.value
        for (find, replacement) in [("gras", "renforcé 😀"), ("**renforcé 😀**", "simple"), ("#", "##"),
                                    ("Fin", "```\nsuite *sans italique*\n```"), ("## Titre", "## Nouveau titre")] {
            let range = (view.string as NSString).range(of: find)
            XCTAssertNotEqual(range.location, NSNotFound)
            view.insertText(replacement, replacementRange: range)
            await coordinator.parseTask?.value
            let fresh = MarkdownTextView(frame: view.frame)
            let reference = MarkdownEditor.Coordinator()
            reference.view = fresh; fresh.delegate = reference; reference.editorFocused = true
            reference.update(text: view.string, noteID: "Reference", zoom: 1, live: true, editable: true, dark: false) { _ in }
            fresh.setSelectedRange(view.selectedRange())
            await reference.parseTask?.value
            XCTAssertEqual(view.textStorage, fresh.textStorage, "Incremental attributes differ after replacing \(find)")
        }
        // Pasting over the whole note may discard native attributes even where
        // the text stayed the same. The actual replacement range must be styled.
        let source = view.string.replacingOccurrences(of: "simple", with: "**simple**")
        view.insertText(source, replacementRange: NSRange(location: 0, length: (view.string as NSString).length))
        await coordinator.parseTask?.value
        let titleFont = try XCTUnwrap(view.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(titleFont.pointSize, 23)
        let code = (source as NSString).range(of: "sans italique").location
        let codeFont = try XCTUnwrap(view.textStorage?.attribute(.font, at: code, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(codeFont.pointSize, 13)
        XCTAssertFalse(NSFontManager.shared.traits(of: codeFont).contains(.italicFontMask))
    }

    @MainActor
    func testTypingNearEndOfLongNoteDoesNotRestyleEarlierParagraphs() async {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
        let source = String(repeating: "Un **cours** avec du texte.\n\n", count: 1000) + "Dernière **note**."
        coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
        await coordinator.parseTask?.value
        let recorder = EditorStorageRecorder()
        view.textStorage?.delegate = recorder
        let caret = (source as NSString).range(of: "note", options: .backwards).location + 2
        view.setSelectedRange(NSRange(location: caret, length: 0))
        recorder.editedRanges = []
        view.insertText("x", replacementRange: view.selectedRange())
        await coordinator.parseTask?.value
        XCTAssertFalse(recorder.editedRanges.isEmpty)
        XCTAssertTrue(recorder.editedRanges.allSatisfy { $0.location > (source as NSString).length - 100 })
        XCTAssertEqual(coordinator.styledSource, view.string)
    }


    @MainActor
    func testInlineAndBlockCodeHaveSeparateDecorationsAndScaleWithZoom() async throws {
        for dark in [false, true] {
            let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
            view.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
            let coordinator = MarkdownEditor.Coordinator()
            coordinator.view = view; view.delegate = coordinator
            let source = "Avant `code` après.\n\n```swift\nlet value = \"**texte**\"\nprint(value)\n```\n\nAprès le bloc."
            coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: dark) { _ in }
            await coordinator.parseTask?.value
            let inline = (source as NSString).range(of: "code").location
            let block = (source as NSString).range(of: "let value").location
            XCTAssertNotNil(view.textStorage?.attribute(.markdownInlineCode, at: inline, effectiveRange: nil))
            XCTAssertNil(view.textStorage?.attribute(.markdownCodeBlock, at: inline, effectiveRange: nil))
            XCTAssertNotNil(view.textStorage?.attribute(.markdownCodeBlock, at: block, effectiveRange: nil))
            XCTAssertNil(view.textStorage?.attribute(.markdownInlineCode, at: block, effectiveRange: nil))
            let literal = (source as NSString).range(of: "**texte**").location
            XCTAssertNil(view.textStorage?.attribute(.markdownConcealed, at: literal, effectiveRange: nil))
            XCTAssertEqual((view.textStorage?.attribute(.paragraphStyle, at: block, effectiveRange: nil) as? NSParagraphStyle)?.headIndent, 12)
            if let path = ProcessInfo.processInfo.environment["ANDORR_EDITOR_RENDER_PATH"], let layout = view.layoutManager {
                layout.ensureLayout(for: view.textContainer!)
                let image = NSImage(size: NSSize(width: 640, height: 400), flipped: true) { bounds in
                    (dark ? NSColor(white: 0.125, alpha: 1) : NSColor.white).setFill()
                    bounds.fill()
                    let glyphs = NSRange(location: 0, length: layout.numberOfGlyphs)
                    layout.drawBackground(forGlyphRange: glyphs, at: NSPoint(x: 20, y: 20))
                    layout.drawGlyphs(forGlyphRange: glyphs, at: NSPoint(x: 20, y: 20))
                    return true
                }
                let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
                let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: path + (dark ? "-dark.png" : "-light.png")))
            }
            coordinator.update(text: source, noteID: "A", zoom: 2, live: true, editable: true, dark: dark) { _ in }
            await coordinator.parseTask?.value
            XCTAssertEqual((view.textStorage?.attribute(.font, at: block, effectiveRange: nil) as? NSFont)?.pointSize, 26)
            XCTAssertEqual((view.textStorage?.attribute(.paragraphStyle, at: block, effectiveRange: nil) as? NSParagraphStyle)?.headIndent, 24)
            coordinator.update(text: source, noteID: "A", zoom: 1, live: false, editable: true, dark: dark) { _ in }
            XCTAssertNil(view.textStorage?.attribute(.markdownInlineCode, at: inline, effectiveRange: nil))
            XCTAssertNil(view.textStorage?.attribute(.markdownCodeBlock, at: block, effectiveRange: nil))
            XCTAssertEqual(view.string, source)
        }
    }

    @MainActor
    func testBashSourceCommandIsHighlightedInLiveEditor() async throws {
        let source = "```bash\nsource ~/.bashrc\n```"
        for dark in [false, true] {
            let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
            let coordinator = MarkdownEditor.Coordinator()
            coordinator.view = view; view.delegate = coordinator
            coordinator.update(text: source, noteID: "Bash", zoom: 1, live: true, editable: true, dark: dark) { _ in }
            await coordinator.parseTask?.value
            let storage = try XCTUnwrap(view.textStorage)
            let command = (source as NSString).range(of: "source").location
            let path = (source as NSString).range(of: "~/.bashrc").location
            let commandColor = try XCTUnwrap(storage.attribute(.foregroundColor, at: command, effectiveRange: nil) as? NSColor)
            let pathColor = try XCTUnwrap(storage.attribute(.foregroundColor, at: path, effectiveRange: nil) as? NSColor)
            XCTAssertNotEqual(commandColor, pathColor, "Bash builtins should be colored: \(commandColor), \(pathColor)")
            if let path = ProcessInfo.processInfo.environment["ANDORR_EDITOR_RENDER_PATH"], let layout = view.layoutManager {
                layout.ensureLayout(for: try XCTUnwrap(view.textContainer))
                let image = NSImage(size: NSSize(width: 600, height: 120), flipped: true) { bounds in
                    (dark ? NSColor(white: 0.125, alpha: 1) : NSColor.white).setFill()
                    bounds.fill()
                    let glyphs = NSRange(location: 0, length: layout.numberOfGlyphs)
                    layout.drawBackground(forGlyphRange: glyphs, at: NSPoint(x: 20, y: 20))
                    layout.drawGlyphs(forGlyphRange: glyphs, at: NSPoint(x: 20, y: 20))
                    return true
                }
                let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
                let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: path + (dark ? "-bash-dark.png" : "-bash-light.png")))
            }
        }
    }

    @MainActor
    func testCodeHighlightingPreservesNativeEditingAndUpdatesThemesAndLanguages() async throws {
        let source = "😀\n```python\n# commentaire\nprint(\"bonjour 😀 & <\")\n```\nSuite"
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.isRichText = false; view.allowsUndo = true
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view; view.delegate = coordinator
        var saved = source
        coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: true) { saved = $0 }
        await coordinator.parseTask?.value
        let stringRange = (source as NSString).range(of: "bonjour")
        let commentRange = (source as NSString).range(of: "commentaire")
        let storage = try XCTUnwrap(view.textStorage)
        let darkColor = try XCTUnwrap(storage.attribute(.foregroundColor, at: stringRange.location, effectiveRange: nil) as? NSColor)
        XCTAssertNotEqual(darkColor, storage.attribute(.foregroundColor, at: commentRange.location, effectiveRange: nil) as? NSColor)
        XCTAssertEqual((storage.attribute(.font, at: stringRange.location, effectiveRange: nil) as? NSFont)?.pointSize, 13)
        XCTAssertEqual((storage.attribute(.paragraphStyle, at: stringRange.location, effectiveRange: nil) as? NSParagraphStyle)?.headIndent, 12)
        view.setSelectedRange(NSRange(location: stringRange.location, length: 0))
        let selection = view.selectedRange()
        coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: false) { saved = $0 }
        await coordinator.parseTask?.value
        let lightColor = storage.attribute(.foregroundColor, at: stringRange.location, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(lightColor, darkColor)
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(view.string, source)
        XCTAssertFalse(view.undoManager?.canUndo ?? true)
        view.insertText("test", replacementRange: selection)
        await coordinator.parseTask?.value
        XCTAssertEqual(saved, view.string)
        view.undo(nil)
        await coordinator.parseTask?.value
        XCTAssertEqual(view.string, source)
        XCTAssertEqual(saved, source)
        coordinator.update(text: source, noteID: "A", zoom: 1, live: false, editable: true, dark: false) { _ in }
        XCTAssertEqual(storage.attribute(.foregroundColor, at: stringRange.location, effectiveRange: nil) as? NSColor,
                       storage.attribute(.foregroundColor, at: commentRange.location, effectiveRange: nil) as? NSColor)
        XCTAssertNil(storage.attribute(.markdownCodeBlock, at: stringRange.location, effectiveRange: nil))
        for language in ["", "unknown-language"] {
            let plain = source.replacingOccurrences(of: "```python", with: "```" + language)
            coordinator.update(text: plain, noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
            await coordinator.parseTask?.value
            let code = (plain as NSString).range(of: "bonjour").location
            XCTAssertEqual(storage.attribute(.foregroundColor, at: code, effectiveRange: nil) as? NSColor,
                           storage.attribute(.foregroundColor, at: (plain as NSString).range(of: "commentaire").location, effectiveRange: nil) as? NSColor)
        }
    }

    func testHighlighterSupportsAliasesUnicodeAndUnfinishedFencesWithoutColoringMarkers() async {
        let highlighter = MarkdownCodeHighlighter()
        for language in ["bash", "sh", "python", "js", "typescript", "swift", "json", "html", "css", "c#"] {
            let source = "Avant 😀\n~~~\(language)\n\"hello 😀 & < >\"\n"
            let spans = MarkdownEditorSyntax.spans(in: source)
            let colors = await highlighter.colors(in: source, spans: spans, dark: false)
            XCTAssertFalse(colors.isEmpty, language)
            let codeStart = (source as NSString).range(of: "\"hello").location
            for token in colors {
                XCTAssertGreaterThanOrEqual(token.range.location, codeStart)
                XCTAssertLessThanOrEqual(NSMaxRange(token.range), (source as NSString).length)
            }
        }
    }

    @MainActor
    func testCodeBlockLanguageUsesOpeningFenceInfoOnly() {
        let layout = MarkdownLayoutManager()
        for (source, expected) in [("```bash\necho hello\n```", "bash"), ("~~~swift extra\nlet x = 1\n~~~", "swift"),
                                   ("```\ncode\n```", nil), ("    indented code", nil), ("```python\n", "python")] {
            let storage = NSTextStorage(string: source)
            storage.addLayoutManager(layout)
            XCTAssertEqual(layout.codeBlockLanguage(forCharacterRange: NSRange(location: 0, length: storage.length)), expected)
            XCTAssertEqual(storage.string, source)
            storage.removeLayoutManager(layout)
        }
    }

    @MainActor
    func testEmptyCodeFenceKeepsTwoFullHeightLinesWhenHiddenOrActive() async throws {
        for source in ["```\n```", "```\n```\nSuite"] {
            for zoom in [1.0, 2.0] {
                let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
                let coordinator = MarkdownEditor.Coordinator()
                coordinator.view = view; view.delegate = coordinator
                coordinator.update(text: source, noteID: "A", zoom: zoom, live: true, editable: true, dark: false) { _ in }
                await coordinator.parseTask?.value
                let layout = try XCTUnwrap(view.layoutManager)
                let container = try XCTUnwrap(view.textContainer)
                for focused in [false, true] {
                    coordinator.editorFocused = focused
                    view.setSelectedRange(NSRange(location: 1, length: 0))
                    coordinator.updateConcealment()
                    layout.ensureLayout(for: container)
                    let opening = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: 0), effectiveRange: nil)
                    let closing = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: 4), effectiveRange: nil)
                    XCTAssertGreaterThanOrEqual(opening.height, 13 * zoom)
                    XCTAssertGreaterThanOrEqual(closing.height, 13 * zoom)
                    XCTAssertGreaterThanOrEqual(closing.minY, opening.maxY - 0.5)
                    XCTAssertEqual(view.string, source)
                }
            }
        }
    }

    @MainActor
    func testFencesStayHiddenInsideCodeAndRevealOnlyOnFenceLines() async {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
        coordinator.update(text: "", noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
        let source = "```swift\nlet x = 1\n```\n\nSuite"
        view.insertText(source, replacementRange: view.selectedRange())
        await coordinator.parseTask?.value
        let markers = coordinator.spans.filter { $0.style == .marker }
        XCTAssertEqual(markers.count, 2)
        view.setSelectedRange(NSRange(location: (source as NSString).range(of: "x =").location, length: 0))
        for marker in markers {
            XCTAssertEqual(view.textStorage?.attribute(.markdownConcealed, at: marker.range.location, effectiveRange: nil) as? Bool, true)
        }
        view.setSelectedRange(NSRange(location: markers[0].range.location + 2, length: 0))
        XCTAssertNil(view.textStorage?.attribute(.markdownConcealed, at: markers[0].range.location, effectiveRange: nil))
        XCTAssertEqual(view.textStorage?.attribute(.markdownConcealed, at: markers[1].range.location, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(view.string, source)
    }

    @MainActor
    func testCodeBlockDoesNotIncludeAdjacentProseWithoutBlankLines() async throws {
        let source = "Si la machine autorise une division registre-registre :\n```\ndiv i, j\nstore i, x\n```\nAprès le code."
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 250, height: 400))
        view.isRichText = false
        view.textContainerInset = NSSize(width: 27, height: 18)
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view; view.delegate = coordinator
        coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
        await coordinator.parseTask?.value
        let layout = try XCTUnwrap(view.layoutManager as? MarkdownLayoutManager)
        let container = try XCTUnwrap(view.textContainer)
        layout.ensureLayout(for: container)
        let block = try XCTUnwrap(coordinator.spans.first { $0.style == .codeBlock })
        let panel = layout.codeBlockRect(forCharacterRange: block.range, in: container)
        let beforeIndex = (source as NSString).range(of: "\n").location - 1
        let beforeGlyph = layout.glyphIndexForCharacter(at: beforeIndex)
        let before = layout.lineFragmentRect(forGlyphAt: beforeGlyph, effectiveRange: nil)
        let afterIndex = (source as NSString).range(of: "Après").location
        let after = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: afterIndex), effectiveRange: nil)
        XCTAssertGreaterThanOrEqual(panel.minY, before.maxY, "The panel includes the preceding paragraph: \(panel), prose: \(before)")
        XCTAssertLessThanOrEqual(panel.maxY, after.minY, "The panel includes following prose")
        XCTAssertNil(view.textStorage?.attribute(.markdownCodeBlock, at: 3, effectiveRange: nil))
        XCTAssertEqual((view.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)?.pointSize, 15)
        XCTAssertEqual(view.string, source)
        coordinator.editorFocused = true
        for caret in [0, (source as NSString).range(of: "div i").location, (source as NSString).range(of: "Après").location] {
            view.setSelectedRange(NSRange(location: caret, length: 0))
            layout.ensureLayout(for: container)
            let updated = layout.codeBlockRect(forCharacterRange: block.range, in: container)
            let prose = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: beforeIndex), effectiveRange: nil)
            XCTAssertGreaterThanOrEqual(updated.minY, prose.maxY, "Caret \(caret): \(updated), prose \(prose)")
        }
        coordinator.update(text: "", noteID: "Typed", zoom: 1, live: true, editable: true, dark: false) { _ in }
        for character in source {
            view.insertText(String(character), replacementRange: view.selectedRange())
            await coordinator.parseTask?.value
        }
        layout.ensureLayout(for: container)
        let typedBlock = try XCTUnwrap(coordinator.spans.first { $0.style == .codeBlock })
        let typedPanel = layout.codeBlockRect(forCharacterRange: typedBlock.range, in: container)
        let typedProse = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: beforeIndex), effectiveRange: nil)
        XCTAssertGreaterThanOrEqual(typedPanel.minY, typedProse.maxY, "Typed panel: \(typedPanel), prose: \(typedProse)")
        XCTAssertNil(view.textStorage?.attribute(.markdownCodeBlock, at: 3, effectiveRange: nil))
        XCTAssertEqual(view.string, source)
        if let path = ProcessInfo.processInfo.environment["ANDORR_EDITOR_RENDER_PATH"] {
            let image = NSImage(size: NSSize(width: 300, height: 300), flipped: true) { bounds in
                NSColor.white.setFill(); bounds.fill()
                let glyphs = NSRange(location: 0, length: layout.numberOfGlyphs)
                layout.drawBackground(forGlyphRange: glyphs, at: NSPoint(x: 20, y: 20))
                layout.drawGlyphs(forGlyphRange: glyphs, at: NSPoint(x: 20, y: 20))
                return true
            }
            let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path + "-adjacent-prose.png"))
        }

    }

    @MainActor
    func testUndoRedoMenuActionsValidateHistoryAndRespectReadOnlyMode() {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.isRichText = false; view.allowsUndo = true
        let undo = NSMenuItem(title: "Annuler", action: #selector(MarkdownTextView.undo(_:)), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Rétablir", action: #selector(MarkdownTextView.redo(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        XCTAssertFalse(view.validateMenuItem(undo))
        XCTAssertFalse(view.validateMenuItem(redo))
        view.undoManager?.groupsByEvent = false
        view.undoManager?.beginUndoGrouping()
        view.insertText("Cours", replacementRange: NSRange(location: 0, length: 0))
        view.breakUndoCoalescing()
        view.undoManager?.endUndoGrouping()
        XCTAssertTrue(view.validateMenuItem(undo))
        XCTAssertFalse(view.validateMenuItem(redo))
        view.isEditable = false
        XCTAssertFalse(view.validateMenuItem(undo))
        view.undo(nil)
        XCTAssertEqual(view.string, "Cours")
        view.isEditable = true
        view.undo(nil)
        XCTAssertEqual(view.string, "")
        XCTAssertFalse(view.validateMenuItem(undo))
        XCTAssertTrue(view.validateMenuItem(redo))
        view.redo(nil)
        XCTAssertEqual(view.string, "Cours")
        XCTAssertFalse(view.validateMenuItem(redo))
    }

    @MainActor
    func testHeadingMarkersStayVisibleThroughTrailingSpacesUntilLeavingTheLine() async {
        for prefix in ["#", "###"] {
            let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
            view.isRichText = false
            let coordinator = MarkdownEditor.Coordinator()
            coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
            coordinator.update(text: "", noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
            for character in prefix + " Bonjour  tout le monde   " {
                view.insertText(String(character), replacementRange: view.selectedRange())
                await coordinator.parseTask?.value
                XCTAssertNil(view.textStorage?.attribute(.markdownConcealed, at: 0, effectiveRange: nil), "Marker vanished after \(view.string.debugDescription)")
            }
            let expectedSize: CGFloat = prefix == "#" ? 28 : 19
            XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, expectedSize)
            let endOfTitle = view.selectedRange().location
            view.insertText("\n", replacementRange: view.selectedRange())
            await coordinator.parseTask?.value
            XCTAssertEqual(view.textStorage?.attribute(.markdownConcealed, at: 0, effectiveRange: nil) as? Bool, true)
            view.setSelectedRange(NSRange(location: endOfTitle, length: 0))
            XCTAssertNil(view.textStorage?.attribute(.markdownConcealed, at: 0, effectiveRange: nil))
            XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, expectedSize)
            view.insertText("!", replacementRange: view.selectedRange())
            await coordinator.parseTask?.value
            XCTAssertNil(view.textStorage?.attribute(.markdownConcealed, at: 0, effectiveRange: nil))
            XCTAssertTrue(view.string.hasSuffix("   !\n"))
        }
    }

    @MainActor
    func testInlineMarkersHideAfterCompletionAndRevealWhenReentering() async {
        for token in ["**gras**", "__gras__", "*italique*", "_italique_", "`code`", "```code```", "[lien](https://example.com)"] {
            let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
            view.isRichText = false
            let coordinator = MarkdownEditor.Coordinator()
            coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
            let source = "Avant " + token + " puis la suite"
            coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
            await coordinator.parseTask?.value
            let region = (source as NSString).range(of: token)
            view.setSelectedRange(NSRange(location: region.location + 3, length: 0))
            for marker in coordinator.spans where marker.style == .marker {
                XCTAssertNil(view.textStorage?.attribute(.markdownConcealed, at: marker.range.location, effectiveRange: nil), token)
            }
            view.setSelectedRange(NSRange(location: NSMaxRange(region), length: 0))
            for marker in coordinator.spans where marker.style == .marker {
                XCTAssertEqual(view.textStorage?.attribute(.markdownConcealed, at: marker.range.location, effectiveRange: nil) as? Bool, true, token)
            }
            view.insertText(" ", replacementRange: view.selectedRange())
            await coordinator.parseTask?.value
            for marker in coordinator.spans where marker.style == .marker {
                XCTAssertEqual(view.textStorage?.attribute(.markdownConcealed, at: marker.range.location, effectiveRange: nil) as? Bool, true, token)
            }
            view.setSelectedRange(NSRange(location: region.location + 3, length: 0))
            for marker in coordinator.spans where marker.style == .marker {
                XCTAssertNil(view.textStorage?.attribute(.markdownConcealed, at: marker.range.location, effectiveRange: nil), token)
            }
            XCTAssertTrue(view.string.contains(token))
        }
    }

    @MainActor
    func testSpaceBeforeClosingDelimiterKeepsFormattingWhileEditing() async throws {
        for delimiter in ["**", "__", "*", "_"] {
            let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
            view.isRichText = false
            let coordinator = MarkdownEditor.Coordinator()
            coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
            let source = delimiter + "Bonjour" + delimiter + "\nSuite"
            coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
            await coordinator.parseTask?.value
            let closing = delimiter.count + 7
            view.setSelectedRange(NSRange(location: closing, length: 0))
            let trait: NSFontTraitMask = delimiter.count == 2 ? .boldFontMask : .italicFontMask
            for character in "  le monde " {
                view.insertText(String(character), replacementRange: view.selectedRange())
                await coordinator.parseTask?.value
                let font = try XCTUnwrap(view.textStorage?.attribute(.font, at: delimiter.count, effectiveRange: nil) as? NSFont)
                XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(trait), view.string)
                XCTAssertTrue(NSFontManager.shared.traits(of: view.typingAttributes[.font] as! NSFont).contains(trait), view.string)
            }
            XCTAssertTrue(view.string.hasPrefix(delimiter + "Bonjour  le monde " + delimiter))
            view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            let font = try XCTUnwrap(view.textStorage?.attribute(.font, at: delimiter.count, effectiveRange: nil) as? NSFont)
            XCTAssertFalse(NSFontManager.shared.traits(of: font).contains(trait))
        }
    }

    @MainActor
    func testHeadingPrefixGetsItsFinalFontBeforeBackgroundRendering() async {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.isRichText = false
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
        coordinator.update(text: "", noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
        await coordinator.parseTask?.value
        for (level, size) in [(1, 28.0), (2, 23.0), (3, 19.0), (4, 16.0), (5, 16.0), (6, 16.0), (7, 15.0)] {
            view.insertText("#", replacementRange: view.selectedRange())
            // No await: native insertion must already have its final geometry.
            XCTAssertEqual((view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, CGFloat(size), "Level \(level)")
            XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, CGFloat(size))
            view.layoutManager?.ensureLayout(for: view.textContainer!)
            let before = view.layoutManager?.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            await coordinator.parseTask?.value
            view.layoutManager?.ensureLayout(for: view.textContainer!)
            XCTAssertEqual(view.layoutManager?.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil), before)
        }
        coordinator.update(text: "Bonjour", noteID: "B", zoom: 1, live: true, editable: true, dark: false) { _ in }
        await coordinator.parseTask?.value
        view.insertText("# ", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual((view.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize, 28)
        view.insertText("", replacementRange: NSRange(location: 0, length: 2))
        XCTAssertEqual((view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 15)
        await coordinator.parseTask?.value
        XCTAssertEqual(view.string, "Bonjour")
    }

    @MainActor
    func testImmediateHeadingStylingRespectsCodeAndRawMode() async {
        for (source, live, expected) in [("```swift\n", true, CGFloat(13)), ("", false, CGFloat(14)), ("\\", true, CGFloat(15))] {
            let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
            let coordinator = MarkdownEditor.Coordinator()
            coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
            coordinator.update(text: source, noteID: "A", zoom: 1, live: live, editable: true, dark: false) { _ in }
            await coordinator.parseTask?.value
            view.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
            view.insertText("#", replacementRange: view.selectedRange())
            let index = (source as NSString).length
            XCTAssertEqual((view.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.pointSize, expected)
            await coordinator.parseTask?.value
            XCTAssertEqual((view.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.pointSize, expected)
        }
    }

    @MainActor
    func testMouseTrackingDefersLayoutUntilReleaseIncludingPendingParse() async {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
        view.selectionTrackingEnded = { [weak coordinator] in coordinator?.finishSelectionTracking() }
        let source = "Un **cours** puis du texte"
        coordinator.update(text: source, noteID: "A", zoom: 1, live: true, editable: true, dark: false) { _ in }
        await coordinator.parseTask?.value
        let before = NSAttributedString(attributedString: view.textStorage!)
        view.beginSelectionTracking()
        view.setSelectedRange(NSRange(location: 6, length: 3))
        coordinator.render() // A background parse may finish during native tracking.
        XCTAssertEqual(view.textStorage, before)
        view.endSelectionTracking()
        XCTAssertNil(view.textStorage?.attribute(.markdownConcealed, at: 3, effectiveRange: nil))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 6, length: 3))
        XCTAssertEqual(view.string, source)
    }

}


private final class EditorStorageRecorder: NSObject, NSTextStorageDelegate {
    var editedRanges: [NSRange] = []
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        if editedMask.contains(.editedAttributes) { editedRanges.append(editedRange) }
    }
}
