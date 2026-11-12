import AppKit
import XCTest
@testable import AndorrDesktop

@MainActor
private struct CompletionEditor {
    let view: MarkdownTextView
    let coordinator: MarkdownEditor.Coordinator

    init(_ source: String = "", live: Bool = true) {
        view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.isRichText = false; view.allowsUndo = true
        coordinator = MarkdownEditor.Coordinator()
        coordinator.view = view; view.delegate = coordinator; coordinator.editorFocused = true
        coordinator.update(text: source, noteID: "A", zoom: 1, live: live, editable: true, dark: false) { _ in }
        view.automaticallyCloseMarkdown = true
        view.undoManager?.groupsByEvent = false
        view.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
    }

    func input(_ text: String) {
        view.undoManager?.beginUndoGrouping()
        view.insertText(text, replacementRange: view.selectedRange())
        view.breakUndoCoalescing()
        view.undoManager?.endUndoGrouping()
    }
}

final class MarkdownCompletionTests: XCTestCase {
    @MainActor
    func testBoldPairPlacesCaretInsideStylesTextAndSkipsItsClosers() async {
        let editor = CompletionEditor()
        editor.input("*")
        XCTAssertEqual(editor.view.string, "**")
        XCTAssertEqual(editor.view.selectedRange(), NSRange(location: 1, length: 0))
        editor.input("*")
        XCTAssertEqual(editor.view.string, "****")
        XCTAssertEqual(editor.view.selectedRange(), NSRange(location: 2, length: 0))
        for letter in "Bonjour" { editor.input(String(letter)) }
        await editor.coordinator.parseTask?.value
        XCTAssertEqual(editor.view.string, "**Bonjour**")
        XCTAssertEqual(editor.view.selectedRange().location, 9)
        let font = editor.view.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as! NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        editor.input("*"); editor.input("*")
        XCTAssertEqual(editor.view.string, "**Bonjour**")
        XCTAssertEqual(editor.view.selectedRange().location, 11)
        for marker in editor.coordinator.spans where marker.style == .marker {
            XCTAssertEqual(editor.view.textStorage?.attribute(.markdownConcealed, at: marker.range.location, effectiveRange: nil) as? Bool, true)
        }
        editor.input(" puis du texte")
        await editor.coordinator.parseTask?.value
        XCTAssertEqual(editor.view.string, "**Bonjour** puis du texte")
        for marker in editor.coordinator.spans where marker.style == .marker {
            XCTAssertEqual(editor.view.textStorage?.attribute(.markdownConcealed, at: marker.range.location, effectiveRange: nil) as? Bool, true)
        }
    }

    @MainActor
    func testUnderscoresWrapUnicodeSelectionAndCanUpgradeToBold() {
        let editor = CompletionEditor("Bonjour 😀")
        let count = (editor.view.string as NSString).length
        editor.view.setSelectedRange(NSRange(location: 0, length: count))
        editor.input("_")
        XCTAssertEqual(editor.view.string, "_Bonjour 😀_")
        XCTAssertEqual(editor.view.selectedRange(), NSRange(location: 1, length: count))
        editor.input("_")
        XCTAssertEqual(editor.view.string, "__Bonjour 😀__")
        XCTAssertEqual(editor.view.selectedRange(), NSRange(location: 2, length: count))
        editor.view.setSelectedRange(NSRange(location: 2 + count, length: 0))
        editor.input("_"); editor.input("_")
        XCTAssertEqual(editor.view.string, "__Bonjour 😀__")
        XCTAssertEqual(editor.view.selectedRange().location, count + 4)
    }

    @MainActor
    func testPairCreationAndEmptyDeletionHaveAtomicUndoAndRedo() {
        let editor = CompletionEditor()
        editor.input("*")
        editor.view.undo(nil)
        XCTAssertEqual(editor.view.string, "")
        editor.view.redo(nil)
        XCTAssertEqual(editor.view.string, "**")
        editor.view.setSelectedRange(NSRange(location: 1, length: 0))
        editor.input("*") // Restored metadata still permits bold promotion.
        XCTAssertEqual(editor.view.string, "****")
        editor.view.deleteBackward(nil)
        XCTAssertEqual(editor.view.string, "")
        XCTAssertEqual(editor.view.selectedRange().location, 0)
        editor.view.undo(nil)
        XCTAssertEqual(editor.view.string, "****")
        editor.view.redo(nil)
        XCTAssertEqual(editor.view.string, "")
    }

    @MainActor
    func testItalicCloserIsSkippedAfterContentAndUndoRestoresTracking() {
        let editor = CompletionEditor()
        editor.input("_")
        editor.input("texte")
        editor.view.undo(nil)
        XCTAssertEqual(editor.view.string, "__")
        editor.view.redo(nil)
        XCTAssertEqual(editor.view.string, "_texte_")
        editor.view.setSelectedRange(NSRange(location: 6, length: 0))
        editor.input("_")
        XCTAssertEqual(editor.view.string, "_texte_")
        XCTAssertEqual(editor.view.selectedRange().location, 7)
    }

    @MainActor
    func testCompletionCanBeDisabledAndNeverCompletesPastedMarkdown() {
        let editor = CompletionEditor()
        editor.view.automaticallyCloseMarkdown = false
        editor.input("*")
        XCTAssertEqual(editor.view.string, "*")
        editor.view.automaticallyCloseMarkdown = true
        editor.input("**collé**")
        XCTAssertEqual(editor.view.string, "***collé**")
        let another = CompletionEditor(live: false)
        another.input("*")
        XCTAssertEqual(another.view.string, "**")
    }

    @MainActor
    func testCodeEscapesIdentifiersAndListsStayLiteral() {
        for source in ["```swift\n", "~~~python\n", "`code`"] {
            let editor = CompletionEditor(source)
            if source == "`code`" { editor.view.setSelectedRange(NSRange(location: 3, length: 0)) }
            let caret = editor.view.selectedRange().location
            editor.input("*")
            XCTAssertEqual((editor.view.string as NSString).length, (source as NSString).length + 1)
            XCTAssertEqual(editor.view.selectedRange().location, caret + 1)
        }
        let afterCode = CompletionEditor("```\nx\n```\n")
        afterCode.input("*")
        XCTAssertTrue(afterCode.view.string.hasSuffix("\n**"))
        let escaped = CompletionEditor("\\")
        escaped.input("*")
        XCTAssertEqual(escaped.view.string, "\\*")
        let identifier = CompletionEditor("variable")
        identifier.input("_")
        XCTAssertEqual(identifier.view.string, "variable_")
        let list = CompletionEditor()
        list.input("*"); list.input(" ")
        XCTAssertEqual(list.view.string, "* ")
    }

    @MainActor
    func testTrackedPairMovesWithEditsBeforeItAndPublishesToAutosaveBinding() {
        let editor = CompletionEditor()
        var saved = ""
        editor.coordinator.onChange = { saved = $0 }
        editor.input("*"); editor.input("bonjour")
        editor.view.setSelectedRange(NSRange(location: 0, length: 0))
        editor.input("😀 ")
        editor.view.setSelectedRange(NSRange(location: (editor.view.string as NSString).length - 1, length: 0))
        editor.input("*")
        XCTAssertEqual(editor.view.string, "😀 *bonjour*")
        XCTAssertEqual(saved, editor.view.string)
        XCTAssertEqual(editor.view.selectedRange().location, (editor.view.string as NSString).length)
    }

    @MainActor
    func testSwitchingNotesClearsOwnedPairsWithoutTouchingManualDelimiters() {
        let editor = CompletionEditor()
        editor.input("*"); editor.input("manual")
        editor.coordinator.update(text: "*manual*", noteID: "B", zoom: 1, live: true, editable: true, dark: false) { _ in }
        editor.view.setSelectedRange(NSRange(location: 7, length: 0))
        editor.input("*")
        XCTAssertEqual(editor.view.string, "*manual***")
    }
    @MainActor
    func testPairInsertionWorksWithDefaultAppKitUndoGrouping() {
        let editor = CompletionEditor()
        editor.view.undoManager?.groupsByEvent = true
        editor.view.insertText("*", replacementRange: editor.view.selectedRange())
        XCTAssertEqual(editor.view.string, "**")
        editor.view.undo(nil)
        XCTAssertEqual(editor.view.string, "")
        editor.view.redo(nil)
        XCTAssertEqual(editor.view.string, "**")
    }

}
