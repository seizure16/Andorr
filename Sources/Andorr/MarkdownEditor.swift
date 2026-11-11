import AppKit
import SwiftUI
import AndorrCore

/// A plain-text editor: formatting is presentation only and never changes the Markdown.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let noteID: String
    let zoom: Double
    let livePreview: Bool
    let editable: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = MarkdownTextView(frame: .zero)
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.usesFindBar = false
        view.usesFontPanel = false
        view.drawsBackground = false
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 27, height: 18)
        view.setAccessibilityLabel("Contenu Markdown")
        scroll.documentView = view
        view.delegate = context.coordinator
        context.coordinator.view = view
        view.focusChanged = { [weak coordinator = context.coordinator] focused in
            coordinator?.editorFocused = focused
            coordinator?.updateConcealment()
        }
        view.selectionTrackingEnded = { [weak coordinator = context.coordinator] in
            coordinator?.finishSelectionTracking()
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(text: text, noteID: noteID, zoom: zoom, live: livePreview,
                                   editable: editable, dark: colorScheme == .dark, onChange: { text = $0 })
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        coordinator.parseTask?.cancel()
        coordinator.view?.delegate = nil
        coordinator.view?.focusChanged = nil
        coordinator.view?.selectionTrackingEnded = nil
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        weak var view: MarkdownTextView?
        var onChange: (String) -> Void = { _ in }
        var noteID: String?
        var zoom = 1.0
        var live = false
        var dark = false
        var updating = false
        var spans: [MarkdownEditorSpan] = []
        var styledSource: String?
        var parseTask: Task<Void, Never>?
        private var parseID = UUID()
        private var renderingDeferred = false
        private var renderedSource: String?
        private var renderedSpans: [MarkdownEditorSpan] = []
        private var renderedZoom = 0.0
        private var renderedLive = false
        private var renderedDark = false
        private var pendingEditedRange: NSRange?
        var editorFocused = false

        func update(text: String, noteID: String, zoom: Double, live: Bool, editable: Bool,
                    dark: Bool, onChange: @escaping (String) -> Void) {
            guard let view else { return }
            self.onChange = onChange
            let changedNote = self.noteID != noteID
            let changedText = view.string != text
            let changedStyle = self.zoom != zoom || self.live != live || self.dark != dark
            self.noteID = noteID; self.zoom = zoom; self.live = live; self.dark = dark
            view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            view.isEditable = editable
            if !editable, view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
            if changedNote || changedText {
                updating = true
                let selection = view.selectedRange()
                view.breakUndoCoalescing()
                view.string = text
                view.undoManager?.removeAllActions()
                let location = changedNote ? 0 : min(selection.location, (text as NSString).length)
                view.setSelectedRange(NSRange(location: location, length: changedNote ? 0 : min(selection.length, (text as NSString).length - location)))
                if changedNote { view.enclosingScrollView?.contentView.scroll(to: .zero) }
                updating = false
                spans = []; styledSource = nil
                renderedSource = nil; pendingEditedRange = nil
            }
            if changedNote || changedText || changedStyle {
                parseTask?.cancel(); parseTask = nil; parseID = UUID()
                render()
                scheduleParse()
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            if !updating, let replacementString {
                let newLength = (replacementString as NSString).length
                let changed = NSRange(location: affectedCharRange.location, length: newLength)
                if let previous = pendingEditedRange {
                    // A broad union is intentional for a burst of edits or a paste.
                    let delta = max(0, newLength - affectedCharRange.length)
                    pendingEditedRange = NSUnionRange(NSRange(location: previous.location, length: previous.length + delta), changed)
                } else { pendingEditedRange = changed }
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !updating, let view else { return }
            onChange(view.string)
            guard !view.hasMarkedText() else { return }
            // One worker consumes the latest snapshot, without waiting for a pause
            // in typing or starting concurrent parses for each keystroke.
            if live { scheduleParse() }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let view, !view.hasMarkedText() else { return }
            if live && styledSource == view.string { updateConcealment() }
            else if live { scheduleParse() }
        }

        func scheduleParse() {
            guard parseTask == nil, live, let view, !view.hasMarkedText() else { return }
            let identity = noteID
            let jobID = UUID()
            parseID = jobID
            parseTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.parseID == jobID, self.noteID == identity,
                          self.live, let view = self.view, !view.hasMarkedText() else { break }
                    let source = view.string
                    let result = await Task.detached(priority: .userInitiated) {
                        MarkdownEditorSyntax.spans(in: source)
                    }.value
                    guard !Task.isCancelled, self.parseID == jobID, self.noteID == identity,
                          !view.hasMarkedText() else { break }
                    if view.string != source { continue }
                    self.spans = result; self.styledSource = source
                    self.render()
                    break
                }
                if let self, self.parseID == jobID { self.parseTask = nil }
            }
        }

        private func markerIsActive(_ span: MarkdownEditorSpan, selection: NSRange) -> Bool {
            guard editorFocused, let scope = span.revealRange else { return false }
            if selection.length > 0 { return NSIntersectionRange(scope, selection).length > 0 }
            return selection.location >= scope.location &&
                (selection.location < NSMaxRange(scope) || (span.revealAtEnd && selection.location == NSMaxRange(scope)))
        }

        func finishSelectionTracking() {
            if renderingDeferred { renderingDeferred = false; render() }
            else { updateConcealment() }
        }

        /// Selection moves only change concealment; fonts and the rest of the
        /// document stay untouched. Native mouse tracking keeps its geometry.
        func updateConcealment() {
            guard !updating, live, let view, !view.isTrackingSelection,
                  !view.hasMarkedText(), styledSource == view.string,
                  let storage = view.textStorage else { return }
            updating = true
            defer { updating = false }
            let origin = view.enclosingScrollView?.contentView.bounds.origin
            let selection = view.selectedRange()
            storage.beginEditing()
            for span in spans where span.style == .marker && NSMaxRange(span.range) <= storage.length {
                let hidden = !markerIsActive(span, selection: selection)
                var needsUpdate = false
                storage.enumerateAttribute(.markdownConcealed, in: span.range) { value, _, _ in
                    if (value as? Bool == true) != hidden { needsUpdate = true }
                }
                guard needsUpdate else { continue }
                if hidden { storage.addAttribute(.markdownConcealed, value: true, range: span.range) }
                else { storage.removeAttribute(.markdownConcealed, range: span.range) }
                view.layoutManager?.invalidateGlyphs(forCharacterRange: span.range, changeInLength: 0, actualCharacterRange: nil)
            }
            storage.endEditing()
            updateTypingAttributes()
            restoreScroll(origin)
        }

        private func restoreScroll(_ origin: NSPoint?) {
            guard let origin, let scroll = view?.enclosingScrollView else { return }
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        private func updateTypingAttributes() {
            guard let view, !view.hasMarkedText() else { return }
            let scale = CGFloat(EditorZoom.normalized(zoom))
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 6 * scale
            var attributes: [NSAttributedString.Key: Any] = [
                .font: live ? NSFont.systemFont(ofSize: 15 * scale) : NSFont.monospacedSystemFont(ofSize: 14 * scale, weight: .regular),
                .foregroundColor: dark ? NSColor(white: 0.9, alpha: 1) : NSColor(white: 0.17, alpha: 1),
                .paragraphStyle: paragraph
            ]
            if live, styledSource == view.string, let storage = view.textStorage {
                let caret = view.selectedRange().location
                let insideStyle = spans.contains {
                    guard $0.style != .marker, caret > $0.range.location else { return false }
                    if case .heading = $0.style { return caret <= NSMaxRange($0.range) }
                    if case .codeBlock = $0.style { return caret <= NSMaxRange($0.range) }
                    return caret < NSMaxRange($0.range)
                }
                if insideStyle, storage.length > 0 {
                    attributes = storage.attributes(at: min(caret, storage.length - 1), effectiveRange: nil)
                    attributes.removeValue(forKey: .markdownConcealed)
                }
            }
            view.typingAttributes = attributes
        }

        func render() {
            guard let view, let storage = view.textStorage, !view.hasMarkedText() else { return }
            guard !view.isTrackingSelection else { renderingDeferred = true; return }
            let source = view.string
            let currentSpans = live && styledSource == source ? spans : []
            var dirty: NSRange?
            if let renderedSource, renderedZoom == zoom, renderedLive == live, renderedDark == dark {
                dirty = MarkdownEditorSyntax.changedRange(from: renderedSource, spans: renderedSpans,
                                                         to: source, spans: currentSpans)
            } else { dirty = NSRange(location: 0, length: storage.length) }
            if let pendingEditedRange {
                let start = min(pendingEditedRange.location, storage.length)
                let clipped = NSRange(location: start, length: min(pendingEditedRange.length, storage.length - start))
                let paragraph = (source as NSString).paragraphRange(for: clipped)
                dirty = dirty.map { NSUnionRange($0, paragraph) } ?? paragraph
            }
            pendingEditedRange = nil
            renderedSource = source; renderedSpans = currentSpans
            renderedZoom = zoom; renderedLive = live; renderedDark = dark
            guard let dirty, dirty.length > 0 else {
                updateTypingAttributes()
                updateConcealment()
                return
            }
            updating = true
            defer { updating = false }
            let scale = CGFloat(EditorZoom.normalized(zoom))
            let font = live ? NSFont.systemFont(ofSize: 15 * scale) : NSFont.monospacedSystemFont(ofSize: 14 * scale, weight: .regular)
            let foreground = dark ? NSColor(white: 0.90, alpha: 1) : NSColor(white: 0.17, alpha: 1)
            let muted = dark ? NSColor(white: 0.55, alpha: 1) : NSColor(white: 0.55, alpha: 1)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 6 * scale
            let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph]
            let origin = view.enclosingScrollView?.contentView.bounds.origin
            let target = NSMutableAttributedString(string: (source as NSString).substring(with: dirty), attributes: base)
            if live, styledSource == view.string {
                for span in spans where NSMaxRange(span.range) <= storage.length {
                    let intersection = NSIntersectionRange(span.range, dirty)
                    guard intersection.length > 0 else { continue }
                    let range = NSRange(location: intersection.location - dirty.location, length: intersection.length)
                    switch span.style {
                    case let .heading(level):
                        let size: CGFloat = level == 1 ? 28 : level == 2 ? 23 : level == 3 ? 19 : 16
                        target.addAttribute(.font, value: NSFont.systemFont(ofSize: size * scale, weight: .semibold), range: range)
                    case .strong, .emphasis:
                        target.enumerateAttribute(.font, in: range) { value, range, _ in
                            let existing = value as? NSFont ?? font
                            let trait: NSFontTraitMask = span.style == .strong ? .boldFontMask : .italicFontMask
                            target.addAttribute(.font, value: NSFontManager.shared.convert(existing, toHaveTrait: trait), range: range)
                        }
                    case .code:
                        target.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 13 * scale, weight: .regular),
                                               .markdownInlineCode: dark ? NSColor(white: 0.20, alpha: 1) : NSColor(white: 0.94, alpha: 1)], range: range)
                    case .codeBlock:
                        let blockParagraph = NSMutableParagraphStyle()
                        blockParagraph.firstLineHeadIndent = 12 * scale
                        blockParagraph.headIndent = 12 * scale
                        blockParagraph.tailIndent = -12 * scale
                        blockParagraph.lineSpacing = 4 * scale
                        target.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 13 * scale, weight: .regular),
                                              .paragraphStyle: blockParagraph,
                                              .markdownCodeBlock: dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.96, alpha: 1)], range: range)
                    case .quote: target.addAttribute(.foregroundColor, value: muted, range: range)
                    case .link: target.addAttribute(.foregroundColor, value: dark ? NSColor(red: 0.65, green: 0.71, blue: 1, alpha: 1) : NSColor(red: 0.26, green: 0.35, blue: 0.66, alpha: 1), range: range)
                    case .marker: break // Apply concealment after all nested font styles.
                    }
                }
            }
            if live, styledSource == view.string {
                for span in spans where span.style == .marker && NSMaxRange(span.range) <= storage.length {
                    let intersection = NSIntersectionRange(span.range, dirty)
                    guard intersection.length > 0 else { continue }
                    let range = NSRange(location: intersection.location - dirty.location, length: intersection.length)
                    if !markerIsActive(span, selection: view.selectedRange()) {
                        target.addAttribute(.markdownConcealed, value: true, range: range)
                    }
                }
            }
            var edits: [(NSRange, [NSAttributedString.Key: Any])] = []
            target.enumerateAttributes(in: NSRange(location: 0, length: target.length)) { desired, range, _ in
                let globalRange = NSRange(location: range.location + dirty.location, length: range.length)
                storage.enumerateAttributes(in: globalRange) { current, subrange, _ in
                    if !NSDictionary(dictionary: current).isEqual(to: desired) { edits.append((subrange, desired)) }
                }
            }
            storage.beginEditing()
            for (range, attributes) in edits { storage.setAttributes(attributes, range: range) }
            storage.endEditing()
            for (range, _) in edits {
                view.layoutManager?.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
            }
            updateTypingAttributes()
            restoreScroll(origin)
            view.insertionPointColor = foreground
            updating = false
            updateConcealment()
        }
    }
}

extension NSAttributedString.Key {
    static let markdownInlineCode = NSAttributedString.Key("org.andorr.markdown.inlineCode")
    static let markdownCodeBlock = NSAttributedString.Key("org.andorr.markdown.codeBlock")
    static let markdownConcealed = NSAttributedString.Key("org.andorr.markdown.concealed")
}

/// Conceal syntax at glyph generation; retain the source and its character indexes.
/// Undo belongs to this editor, never to another note or a settings text field.
final class MarkdownTextView: NSTextView, NSLayoutManagerDelegate {
    var focusChanged: ((Bool) -> Void)?
    var selectionTrackingEnded: (() -> Void)?
    private(set) var isTrackingSelection = false

    override func mouseDown(with event: NSEvent) {
        beginSelectionTracking()
        super.mouseDown(with: event)
        endSelectionTracking()
    }

    func beginSelectionTracking() { isTrackingSelection = true }
    func endSelectionTracking() {
        isTrackingSelection = false
        selectionTrackingEnded?()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged?(false) }
        return accepted
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes indexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        let text = storage.string as NSString
        var properties = Array(UnsafeBufferPointer(start: props, count: range.length))
        var changed = false
        for index in 0..<range.length {
            let character = indexes[index]
            guard character < storage.length,
                  storage.attribute(.markdownConcealed, at: character, effectiveRange: nil) as? Bool == true else { continue }
            // Preserve paragraph boundaries even when a marker spans multiple lines.
            let codeUnit = text.character(at: character)
            guard codeUnit != 10 && codeUnit != 13 else { continue }
            properties[index].insert(.null)
            changed = true
        }
        guard changed else { return 0 }
        properties.withUnsafeBufferPointer {
            layoutManager.setGlyphs(glyphs, properties: $0.baseAddress!, characterIndexes: indexes, font: font, forGlyphRange: range)
        }
        return range.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineRect: NSRectPointer,
                       lineFragmentUsedRect usedRect: NSRectPointer, baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in container: NSTextContainer, forGlyphRange range: NSRange) -> Bool {
        guard let storage = layoutManager.textStorage else { return false }
        let characters = layoutManager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
        guard characters.length > 0 else { return false }
        let text = storage.string as NSString
        var hiddenFence = false
        for index in characters.location..<NSMaxRange(characters) {
            let unit = text.character(at: index)
            if unit == 10 || unit == 13 { continue }
            guard storage.attribute(.markdownCodeBlock, at: index, effectiveRange: nil) != nil,
                  storage.attribute(.markdownConcealed, at: index, effectiveRange: nil) as? Bool == true else { return false }
            hiddenFence = true
        }
        if !hiddenFence, characters.location > 0 {
            let previous = characters.location - 1
            hiddenFence = storage.attribute(.markdownCodeBlock, at: previous, effectiveRange: nil) != nil &&
                storage.attribute(.markdownConcealed, at: previous, effectiveRange: nil) as? Bool == true
        }
        guard hiddenFence else { return false }
        let font = storage.attribute(.font, at: min(NSMaxRange(characters) - 1, storage.length - 1), effectiveRange: nil) as? NSFont
        let padding = 8 * (font?.pointSize ?? 13) / 13
        lineRect.pointee.size.height = padding
        usedRect.pointee.size.height = padding
        baselineOffset.pointee = 0
        return true
    }

    // Expose standard responder actions so the Edit menu's keyboard shortcuts
    // reach this editor's own undo manager rather than the window's history.
    @IBAction func undo(_ sender: Any?) {
        guard isEditable, !hasMarkedText(), textUndoManager.canUndo else { return }
        breakUndoCoalescing()
        textUndoManager.undo()
    }

    @IBAction func redo(_ sender: Any?) {
        guard isEditable, !hasMarkedText(), textUndoManager.canRedo else { return }
        breakUndoCoalescing()
        textUndoManager.redo()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return isEditable && !hasMarkedText() && textUndoManager.canUndo }
        if item.action == #selector(redo(_:)) { return isEditable && !hasMarkedText() && textUndoManager.canRedo }
        return super.validateUserInterfaceItem(item)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undo(_:)) || menuItem.action == #selector(redo(_:)) {
            return validateUserInterfaceItem(menuItem)
        }
        return super.validateMenuItem(menuItem)
    }

    private let textUndoManager = UndoManager()
    private var ownedStorage: NSTextStorage?
    override var undoManager: UndoManager? { textUndoManager }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer? = nil) {
        let textContainer: NSTextContainer
        if let container {
            textContainer = container
        } else {
            let storage = NSTextStorage()
            let layout = MarkdownLayoutManager()
            textContainer = NSTextContainer(size: NSSize(width: frameRect.width, height: CGFloat.greatestFiniteMagnitude))
            storage.addLayoutManager(layout)
            layout.addTextContainer(textContainer)
            ownedStorage = storage
        }
        super.init(frame: frameRect, textContainer: textContainer)
        layoutManager?.delegate = self
        observeHistory()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layoutManager?.delegate = self
        observeHistory()
    }

    private func observeHistory() {
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(historyChanged), name: name, object: textUndoManager)
        }
    }

    @objc private func historyChanged(_ notification: Notification) {
        // UndoManager can edit storage without the normal text-input notification.
        // Publish the final text so autosave observes undo/redo as well as typing.
        didChangeText()
    }
}


/// Background decoration stays separate from glyphs, source text and selection.
final class MarkdownLayoutManager: NSLayoutManager {
    func codeBlockRect(forCharacterRange range: NSRange, in container: NSTextContainer) -> NSRect {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var bounds = NSRect.null
        enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in bounds = bounds.union(rect) }
        guard !bounds.isNull, let storage = textStorage else { return .null }
        let text = storage.string as NSString
        // Zero-width fence glyphs can share a native line fragment with an
        // adjacent paragraph. Clip decoration to the source paragraph boundaries
        // instead of trusting the union of glyph fragments alone.
        let start = text.paragraphRange(for: NSRange(location: range.location, length: 0)).location
        if start > 0 {
            let previousGlyph = glyphIndexForCharacter(at: start - 1)
            let previousLine = lineFragmentRect(forGlyphAt: previousGlyph, effectiveRange: nil)
            let top = max(bounds.minY, previousLine.maxY)
            bounds = NSRect(x: bounds.minX, y: top, width: bounds.width, height: max(0, bounds.maxY - top))
        }
        var nextParagraph = 0
        text.getLineStart(nil, end: &nextParagraph, contentsEnd: nil,
                          for: NSRange(location: max(range.location, NSMaxRange(range) - 1), length: 0))
        if nextParagraph < text.length {
            let nextGlyph = glyphIndexForCharacter(at: nextParagraph)
            let nextLine = lineFragmentRect(forGlyphAt: nextGlyph, effectiveRange: nil)
            bounds.size.height = max(0, min(bounds.maxY, nextLine.minY) - bounds.minY)
        }
        let inset = container.lineFragmentPadding
        return NSRect(x: inset, y: bounds.minY, width: max(0, container.size.width - 2 * inset), height: bounds.height)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, glyphsToShow.length > 0,
              let container = textContainers.first else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.markdownCodeBlock, in: characters) { value, range, _ in
            guard let color = value as? NSColor else { return }
            var fullRange = NSRange()
            _ = storage.attribute(.markdownCodeBlock, at: range.location, longestEffectiveRange: &fullRange,
                                  in: NSRange(location: 0, length: storage.length))
            let bounds = self.codeBlockRect(forCharacterRange: fullRange, in: container)
            guard !bounds.isNull else { return }
            let rect = bounds.offsetBy(dx: origin.x, dy: origin.y)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }
        storage.enumerateAttribute(.markdownInlineCode, in: characters) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            self.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                         in: container) { bounds, _ in
                guard bounds.width > 0 else { return }
                color.setFill()
                let rect = bounds.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -1, dy: 1)
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            }
        }
        // Native selection and marked-text backgrounds must remain above the panels.
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}
