import AppKit

/// A native text system on the canvas: selection, marked text/IME, clipboard and local undo
/// stay with NSTextView. Its logical bounds are layer pixels; the containing view supplies zoom.
/// Its glyphs are clear: the canvas draws the text as the layer's own pixels underneath, as Photoshop does, so
/// what is typed looks the same at any zoom as it will once it is committed.
/// Selection and insertion geometry use the letters' ascent and descent, independent of leading.
private nonisolated final class SeeThroughSelectionLayout: VerticalEmLayoutManager {
    var columnSpacing: CGFloat = 0
    /// The letters on a laid-out line, including all its faces. A blank line uses the typing face.
    private func letters(on line: NSRange, fragment: CGRect, typingFont: NSFont?) -> CGRect? {
        guard let storage = textStorage else { return nil }
        let characters = characterRange(forGlyphRange: line, actualGlyphRange: nil)
        let content = (storage.string as NSString).substring(with: characters)
        if textContainers.first?.layoutOrientation == .vertical {
            let measured = measureEmBounds(for: line)
            if !measured.isNull { return measured }
            guard let font = typingFont else { return nil }
            return CGRect(x: fragment.minX, y: fragment.minY + columnSpacing - font.pointSize,
                          width: fragment.width, height: font.pointSize)
        }
        var ascent: CGFloat = 0, descent: CGFloat = 0
        if content.trimmingCharacters(in: .newlines).isEmpty, let font = typingFont {
            ascent = font.ascender
            descent = abs(font.descender)
        } else {
            storage.enumerateAttribute(.font, in: characters, options: []) { value, _, _ in
                if let font = value as? NSFont {
                    ascent = max(ascent, font.ascender)
                    descent = max(descent, abs(font.descender))
                }
            }
        }
        guard ascent + descent > 0 else { return nil }
        let baseline = fragment.minY + location(forGlyphAt: line.location).y
        return CGRect(x: fragment.minX, y: baseline - ascent, width: fragment.width, height: ascent + descent)
    }

    private func letterBounds(atY y: CGFloat, typingFont: NSFont?) -> CGRect? {
        guard let container = textContainers.first else { return nil }
        ensureLayout(for: container)
        if extraLineFragmentTextContainer === container, numberOfGlyphs == 0 || y >= extraLineFragmentRect.minY {
            guard let font = typingFont else { return nil }
            let fragment = extraLineFragmentRect
            if container.layoutOrientation == .vertical {
                return CGRect(x: fragment.minX, y: fragment.minY + columnSpacing - font.pointSize,
                              width: fragment.width, height: font.pointSize)
            }
            return CGRect(x: fragment.minX, y: fragment.maxY - abs(font.descender) - font.ascender,
                          width: fragment.width, height: font.ascender + abs(font.descender))
        }
        guard numberOfGlyphs > 0 else { return nil }
        var line = NSRange()
        let glyph = glyphIndex(for: CGPoint(x: 0, y: y), in: container)
        let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: &line)
        return letters(on: line, fragment: fragment, typingFont: typingFont)
    }

    func coveringLetters(_ rect: CGRect, origin: CGPoint, typingFont: NSFont?) -> CGRect {
        // AppKit's caret position distinguishes both sides of a soft wrap at the same character index.
        let y = rect.minY + min(1, rect.height / 2) - origin.y
        guard let letters = letterBounds(atY: y, typingFont: typingFont) else { return rect }
        return CGRect(x: rect.minX, y: letters.minY + origin.y, width: rect.width, height: letters.height)
    }

    /// NSTextView clips its layout manager's background drawing to the line fragments. A short leading's letters
    /// stand above that clip, so the selection is painted by the text view before it enters that drawing stage.
    func selectionRects(_ ranges: [NSRange], origin: CGPoint, typingFont: NSFont?) -> [CGRect] {
        guard let container = textContainers.first else { return [] }
        ensureLayout(for: container)
        var rects: [CGRect] = []
        for range in ranges where range.length > 0 {
            let selected = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: selected) { fragment, _, _, line, _ in
                guard let letters = self.letters(on: line, fragment: fragment, typingFont: typingFont) else { return }
                self.enumerateEnclosingRects(forGlyphRange: NSIntersectionRange(line, selected),
                    withinSelectedGlyphRange: selected, in: container) { rect, _ in
                    rects.append(CGRect(x: rect.minX + origin.x, y: letters.minY + origin.y,
                                        width: rect.width, height: letters.height))
                }
            }
        }
        return rects
    }

    /// What `drawSelection` last painted, which AppKit's own selection fill then leaves alone.
    private var paintedSelection: [NSRange] = []

    func drawSelection(_ ranges: [NSRange], origin: CGPoint, typingFont: NSFont?, color: NSColor) {
        paintedSelection = ranges.filter { $0.length > 0 }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rects = selectionRects(ranges, origin: origin, typingFont: typingFont)
        context.saveGState()
        defer { context.restoreGState() }
        color.withAlphaComponent(min(color.alphaComponent, 0.45)).setFill()
        // One nonzero-winding fill keeps overlapping lines at the same opacity.
        context.addRects(rects)
        context.fillPath()
    }

    // The selection is painted above, focused or not. AppKit would paint it again, as tall as the leading, and once
    // the text loses the focus — to the font size field, or the color picker — in solid gray over the letters.
    // Any other background stays see-through to the letters too.
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
                                          forCharacterRange charRange: NSRange, color: NSColor) {
        if paintedSelection.contains(where: { NSIntersectionRange($0, charRange).length > 0 }) { return }
        color.withAlphaComponent(min(color.alphaComponent, 0.45)).setFill()
        super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
    }
}

/// The native insertion callback supplies position and blinking, but its graphics clip is only as tall as leading.
/// A separate view can cover the letters outside that clip, and lets clicks reach the text beneath it.
private final class CanvasTextCaret: NSView {
    var color = NSColor.textColor { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) { color.setFill(); bounds.fill() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class CanvasTextView: NSTextView {
    weak var editor: InlineTextEditor?
    private let textUndo = UndoManager()
    /// Set when the font menu takes the focus, so a collapsed caret does not replace the letters that were selected.
    var holdsSelection = false
    /// How far letters stand out of the top of their line, at most, which a leading shorter than they are tall leaves
    /// them doing. In a vertical view native y points left, so this same reach extends toward the right.
    var letterReach: CGFloat = 0
    private let caretView = CanvasTextCaret(frame: .zero)
    private func installCaret() {
        guard caretView.superview == nil else { return }
        caretView.wantsLayer = true
        caretView.isHidden = true
        caretView.setAccessibilityElement(false)
        caretView.identifier = NSUserInterfaceItemIdentifier("canvasTextCaret")
        addSubview(caretView)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { installCaret() }
    }
    var selectionRects: [CGRect] {
        (layoutManager as? SeeThroughSelectionLayout)?.selectionRects(selectedRanges.map(\.rangeValue),
            origin: textContainerOrigin, typingFont: typingAttributes[.font] as? NSFont) ?? []
    }
    override func draw(_ dirtyRect: NSRect) {
        (layoutManager as? SeeThroughSelectionLayout)?.drawSelection(selectedRanges.map(\.rangeValue),
            origin: textContainerOrigin, typingFont: typingAttributes[.font] as? NSFont,
            color: NSColor.selectedTextBackgroundColor)
        super.draw(dirtyRect)
    }
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        installCaret()
        let caret = (layoutManager as? SeeThroughSelectionLayout)?.coveringLetters(rect, origin: textContainerOrigin,
            typingFont: typingAttributes[.font] as? NSFont) ?? rect
        if caretView.frame != caret { caretView.frame = caret }
        caretView.color = color
        // AppKit owns the on/off clock. Paint in a child view instead of its line-height graphics clip.
        caretView.isHidden = !flag || selectedRange().length > 0 || window?.firstResponder !== self || window?.isKeyWindow != true
    }
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: flag)
        if selectedRange().length > 0 { caretView.isHidden = true }
        // A native selection invalidates only its line fragments, leaving a short leading's highlights above them.
        needsDisplay = true
    }
    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var rect = rect
        if letterReach > 0, !rect.isEmpty { rect.origin.y -= letterReach; rect.size.height += letterReach }
        super.setNeedsDisplay(rect, avoidAdditionalLayout: flag)
    }
    override var undoManager: UndoManager? { textUndo }
    // Undo and Redo reach the window, whose history isn't this one, so the text answers them itself: ⌘Z takes back
    // what was typed since the text box opened, in one step, as in Figma.
    @objc func undo(_ sender: Any?) { if textUndo.canUndo { textUndo.undo() } }
    @objc func redo(_ sender: Any?) { if textUndo.canRedo { textUndo.redo() } }
    override func resignFirstResponder() -> Bool {
        // The font menu takes the focus and can collapse the highlight. The letters stay selected, so the face
        // applies to them.
        let range = selectedRange()
        let resigned = super.resignFirstResponder()
        if resigned { caretView.isHidden = true; needsDisplay = true }
        if range.length > 0 {
            holdsSelection = true
            editor?.keepSelection(range)
        }
        return resigned
    }
    override func mouseDown(with event: NSEvent) {
        holdsSelection = false
        super.mouseDown(with: event)
    }
    /// Keep AppKit's editing commands while offering placement changes for the open text draft.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())
        for (title, horizontal) in [("Flip Horizontal", true), ("Flip Vertical", false)] {
            let item = NSMenuItem(title: title, action: #selector(flipTextFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = horizontal ? 1 : 0
            menu.addItem(item)
        }
        return menu
    }
    @objc private func flipTextFromMenu(_ sender: NSMenuItem) {
        editor?.canvas?.session.flipText(horizontally: sender.tag == 1)
    }
    override func keyDown(with event: NSEvent) {
        guard let event = ShortcutSettings.shared.textEvent(event) else { return }
        // While an input method is composing, Esc is its own: it gives up the conversion, not the whole text box.
        if event.keyCode == 53, !hasMarkedText() { editor?.canvas?.session.cancelText(); return }
        // Option with the arrows sets spacing, as in Photoshop: left and right the tracking, up and down the
        // leading. Shift makes each step ten.
        if event.modifierFlags.contains(.option), [123, 124, 125, 126].contains(event.keyCode),
           let session = editor?.canvas?.session {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            switch event.keyCode {
            case 123: session.changeTextStyle { $0.tracking -= step }
            case 124: session.changeTextStyle { $0.tracking += step }
            // Up closes the lines up, down opens them out, counting from whatever Auto works out to.
            case 126: session.changeTextStyle { $0.leading = max(1, $0.lineHeight - step) }
            default: session.changeTextStyle { $0.leading = $0.lineHeight + step }
            }
            return
        }
        if (event.keyCode == 36 || event.keyCode == 76), event.modifierFlags.contains(.command) {
            _ = editor?.canvas?.session.finishText()
            return
        }
        holdsSelection = false
        super.keyDown(with: event)
        // Text views hide the pointer while typing; on the canvas it stays, so you can see where you'll click next.
        NSCursor.setHiddenUntilMouseMoves(false)
    }
    // What an input method is still composing isn't reported as a change until it is committed, and the letters here
    // are clear: the canvas draws only what the draft holds, so kanji and kana stayed invisible until Return.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        editor?.takeText()
    }
    // Esc an input method passed back while it was composing gives up what it was composing, and the text box stays
    // open. With nothing being composed, it closes the box, as Esc does.
    override func cancelOperation(_ sender: Any?) {
        guard hasMarkedText() else { editor?.canvas?.session.cancelText(); return }
        inputContext?.discardMarkedText()
        if hasMarkedText() { insertText("", replacementRange: markedRange()) }
    }
    override func mouseExited(with event: NSEvent) { NSCursor.setHiddenUntilMouseMoves(false) }
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
    // The editor sets the cursor for the whole box — the I-beam over the text, resize arrows over the edges.
    override func resetCursorRects() {}
}

/// A view transform, unlike a layer-only mirror, also maps native text hit tests and IME rectangles.
private final class CanvasTextSurface: NSView {
    override var isFlipped: Bool { true }
    private var mirror = CGSize(width: 1, height: 1)
    func place(size: CGSize, flipX: Bool, flipY: Bool) {
        scaleUnitSquare(to: mirror)
        frame = CGRect(origin: .zero, size: size)
        bounds = CGRect(origin: .zero, size: size)
        mirror = CGSize(width: flipX ? -1 : 1, height: flipY ? -1 : 1)
        scaleUnitSquare(to: mirror)
        translateOrigin(to: CGPoint(x: flipX ? -size.width : 0, y: flipY ? -size.height : 0))
    }
}

final class InlineTextEditor: NSView, NSTextViewDelegate {
    weak var canvas: CanvasView?
    let textView = CanvasTextView(frame: .zero)
    private let textSurface = CanvasTextSurface(frame: .zero)
    fileprivate var draftID: UUID?
    private var shownStyle: LayerTextStyle?
    /// The style after an edit NSTextView has accepted but not yet made, with its color and font runs moved to fit.
    private var pendingStyle: LayerTextStyle?
    private var synchronizing = false
    private var logicalSize = CGSize(width: 360, height: 160)
    private var handleSize: CGFloat = 6
    private(set) var shownTransform: LayerTransform?
    private struct Geometry: Equatable {
        let transform: LayerTransform
        let logicalSize: CGSize
        let anchor: CGPoint
        let scale: CGFloat
        let overflow: CGFloat
        let vertical: Bool
    }
    private var shownGeometry: Geometry?
    private var measuredStyle: LayerTextStyle?
    private var measuredSize: CGSize = .zero
    /// How much lower than its padding the first line is set, as the canvas draws it (see `EditorSession.firstLine`).
    private var measuredOverflow: CGFloat = 0
    private var verticalLayout: VerticalTextLayout?
    private var resize: (handle: Int, draft: TextDraft, transform: LayerTransform, start: CGPoint)?
    /// A rotation under way: the drag as the Move tool does it, its draft, and the corner its cursor follows.
    private var turn: (drag: TransformDrag, draft: TextDraft, corner: CGPoint)?
    /// The transform the editor is actually showing. Point text grows as it is typed, so this is not always the
    /// draft's own transform, and a resize has to start from what is on screen or the text jumps.
    override var isFlipped: Bool { true }

    init(canvas: CanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)
        textView.editor = self
        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        // The selection shows through to the text the canvas draws beneath it, also while another window (the color
        // picker previewing the selected letters) has focus, where AppKit would otherwise paint it solid gray.
        textView.selectedTextAttributes = [.backgroundColor: NSColor.clear]
        textView.textContainer?.replaceLayoutManager(SeeThroughSelectionLayout())
        textView.setAccessibilityLabel("Canvas text")
        // Create backing layers before attachment so the text starts in its final layer hierarchy.
        // synchronize reflects the view coordinates before the editor becomes visible.
        wantsLayer = true
        textView.wantsLayer = true
        addSubview(textSurface)
        textSurface.addSubview(textView)
        textSurface.clipsToBounds = false
        clipsToBounds = false
        // Shown once it has been placed, so a flipped layer never appears for a frame at the unmirrored spot.
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func synchronize(_ draft: TextDraft) {
        guard let canvas, let document = canvas.session.document else { return }
        let fresh = draftID != draft.id
        draftID = draft.id
        let style = draft.style
        let layer = document.layers.first { $0.id == draft.layerID }
        if measuredStyle != style {
            // Point text has no box: it is as big as what has been typed, growing as it is typed. A box is its own size.
            measuredSize = EditorSession.textBoxSize(style)
            verticalLayout = style.isVertical ? EditorSession.verticalLayout(style, size: measuredSize) : nil
            measuredOverflow = verticalLayout?.columnOffset ?? EditorSession.firstLine(style).overflow
            textView.letterReach = style.isVertical ? max(0, measuredOverflow)
                : EditorSession.letterMetrics(style, in: NSRange(location: 0, length: style.content.utf16.count)).overflow
            measuredStyle = style
        }
        logicalSize = measuredSize
        var placed = draft
        let transform = placed.textTransform(size: logicalSize, layer: layer)
        if canvas.session.textDraft?.pointPlacement != placed.pointPlacement {
            canvas.session.textDraft?.pointPlacement = placed.pointPlacement
        }
        let orientation: NSLayoutManager.TextLayoutOrientation = style.isVertical ? .vertical : .horizontal
        if textView.layoutOrientation != orientation { textView.setLayoutOrientation(orientation) }
        (textView.layoutManager as? SeeThroughSelectionLayout)?.columnSpacing = style.lineHeight
        shownTransform = transform
        let scale = canvas.session.viewport.pointsPerPixel
        let anchor = canvas.session.viewport.viewPoint(from: transform.point(.zero), documentSize: document.size)
        let geometry = Geometry(transform: transform, logicalSize: logicalSize, anchor: anchor, scale: scale, overflow: measuredOverflow, vertical: style.isVertical)
        if fresh || shownGeometry != geometry {
            // AppKit's frame rotation participates in both drawing and event-coordinate conversion.
            frameRotation = 0
            frame = CGRect(origin: canvas.session.viewport.viewPoint(from: transform.point(.zero), documentSize: document.size),
                           size: CGSize(width: transform.size.width * scale, height: transform.size.height * scale))
            bounds = CGRect(origin: .zero, size: logicalSize)
            // The canvas is flipped, so a positive frame rotation turns the editor clockwise on screen, the way a layer's
            // own rotation is measured. Negating it turned the editor the opposite way from the text it is editing.
            frameRotation = transform.rotation
            // Rotating a flipped NSView can move its logical origin. Keep the layer's top-left pinned.
            let actual = convert(CGPoint.zero, to: canvas)
            setFrameOrigin(CGPoint(x: frame.origin.x + anchor.x - actual.x, y: frame.origin.y + anchor.y - actual.y))
            // The text is laid out where the canvas draws it, a short leading's first line lower than the padding. The
            // text container moves down rather than the text view, which keeps the room above that line where its
            // letters stand, and its caret and highlight with them; the inset leaves as much again past the bottom.
            let padding = LayerTextStyle.padding, overflow = measuredOverflow
            let textFrame: CGRect, inset: CGSize, containerSize: CGSize
            if let verticalLayout {
                textFrame = CGRect(x: padding, y: padding, width: max(0, bounds.width - padding * 2),
                                   height: max(0, bounds.height - padding * 2))
                inset = CGSize(width: 0, height: verticalLayout.columnOffset)
                containerSize = verticalLayout.container.size
            } else {
                let room = max(0, bounds.height - padding * 2 - overflow)
                textFrame = CGRect(x: padding, y: padding, width: max(0, bounds.width - padding * 2), height: room + overflow * 2)
                inset = CGSize(width: 0, height: overflow)
                containerSize = CGSize(width: textFrame.width, height: room)
            }
            textView.textContainer?.widthTracksTextView = !style.isVertical
            textView.textContainer?.heightTracksTextView = !style.isVertical
            if textView.textContainerInset != inset { textView.textContainerInset = inset }
            if textView.frame != textFrame { textView.frame = textFrame }
            if let container = textView.textContainer, container.size != containerSize { container.size = containerSize }
            // Reflect input and drawing together, before the first layout or visible frame. The surrounding
            // editor keeps its border and resize handles in their unmirrored logical order.
            textSurface.place(size: logicalSize, flipX: transform.flipX, flipY: transform.flipY)
            handleSize = max(2, 6 / max(0.01, scale * transform.size.width / logicalSize.width))
            shownGeometry = geometry
            needsDisplay = true
        }
        if shownStyle != style {
            synchronizing = true
            let live = textView.selectedRange()
            let kept = canvas.session.textDraft?.selection ?? live
            let selection = textView.holdsSelection && kept.length > 0 ? kept : live
            if textView.string != style.content { textView.string = style.content }
            var attributes = EditorSession.textAttributes(style)
            attributes[.foregroundColor] = NSColor.clear
            if !textView.hasMarkedText() {
                textView.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: textView.string.utf16.count))
                for run in style.fontRuns ?? [] where EditorSession.containsTextRun(run.location, run.length, in: textView.string.utf16.count) {
                    let font = NSFont(name: run.fontName, size: style.fontSize) ?? NSFont.systemFont(ofSize: style.fontSize)
                    textView.textStorage?.addAttribute(.font, value: font, range: NSRange(location: run.location, length: run.length))
                }
                textView.setSelectedRange(NSRange(location: min(selection.location, textView.string.utf16.count),
                    length: min(selection.length, max(0, textView.string.utf16.count - selection.location))))
            }
            let caret = selection.length > 0 ? selection.location : max(0, selection.location - 1)
            let face = style.fontName(at: caret)
            attributes[.font] = NSFont(name: face, size: style.fontSize) ?? NSFont.systemFont(ofSize: style.fontSize)
            textView.typingAttributes = attributes
            shownStyle = style
            updateInsertionPointColor(style)
            synchronizing = false
            needsDisplay = true
        }
        if isHidden { isHidden = false }
        if fresh {
            textView.undoManager?.removeAllActions()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.canvas?.session.textDraft?.id == draft.id else { return }
                if self.window?.firstResponder is NSText, self.window?.firstResponder !== self.textView { return }
                self.window?.makeFirstResponder(self.textView)
                // Opening existing text puts the cursor after it, ready to add to it, unless a click already placed it.
                if draft.layerID != nil, self.textView.selectedRange() == NSRange(location: 0, length: 0) {
                    self.textView.setSelectedRange(NSRange(location: self.textView.string.utf16.count, length: 0))
                }
            }
        }
    }

    func textDidChange(_ notification: Notification) { takeText() }
    /// Puts what the text view holds into the draft, which is what the canvas draws: what has been typed, and what an
    /// input method is still composing.
    func takeText() {
        guard !synchronizing, let session = canvas?.session, var draft = session.textDraft else { return }
        if let pendingStyle, pendingStyle.content == textView.string {
            draft.style.colorRuns = pendingStyle.colorRuns
            draft.style.fontRuns = pendingStyle.fontRuns
        }
        pendingStyle = nil
        draft.style.content = textView.string
        // Text NSTextView changed without saying how can't keep its colors and faces letter for letter.
        if !draft.style.isValid { draft.style.colorRuns = nil; draft.style.fontRuns = nil }
        draft.selection = textView.selectedRange()
        shownStyle = draft.style
        session.textDraft = draft
        // NSTextView draws the changed glyphs itself. Refresh the box's overflow marker
        // without resetting the text container's geometry on every keystroke.
        needsDisplay = true
    }
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let length = replacementString?.utf16.count ?? 0
        guard textView.string.utf16.count - affectedCharRange.length + length <= 100_000 else { return false }
        if !synchronizing, let draft = canvas?.session.textDraft,
           draft.style.colorRuns != nil || draft.style.fontRuns != nil {
            var style = pendingStyle ?? draft.style
            guard NSMaxRange(affectedCharRange) <= style.content.utf16.count else { return true }
            style.replaceCharacters(in: affectedCharRange, withLength: length)
            style.content = (style.content as NSString).replacingCharacters(in: affectedCharRange, with: replacementString ?? "")
            pendingStyle = style
        }
        return true
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        guard !synchronizing, let session = canvas?.session, session.textDraft?.id == draftID else { return }
        let selection = textView.selectedRange()
        if textView.holdsSelection, selection.length == 0, (session.textDraft?.selection.length ?? 0) > 0 { return }
        textView.holdsSelection = false
        if session.textDraft?.selection != selection { session.textDraft?.selection = selection }
        if let style = session.textDraft?.style { updateInsertionPointColor(style) }
    }
    /// Puts back a selection a focus change wiped, so the font menu still edits those letters.
    func keepSelection(_ range: NSRange) {
        guard range.length > 0, let session = canvas?.session, session.textDraft?.id == draftID else { return }
        if session.textDraft?.selection != range { session.textDraft?.selection = range }
    }
    private func updateInsertionPointColor(_ style: LayerTextStyle) {
        let location = textView.selectedRange().location
        let color = style.color(at: location > 0 ? location - 1 : 0)
        textView.insertionPointColor = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

    private var handleTracking: NSTrackingArea?
    /// The cursor follows the same test the mouse does: arrows over the edges and corners, the rotation cursor just
    /// outside a corner, the I-beam over the text. Cursor rects are no use here — the box can be rotated, and AppKit
    /// does not map them through a view's rotation — so this view watches the pointer itself.
    private var cursorTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow,
                                                         .mouseEnteredAndExited, .mouseMoved, .cursorUpdate], owner: self)
        addTrackingArea(area)
        cursorTracking = area
    }
    override func mouseEntered(with event: NSEvent) { showCursor(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { showCursor(at: convert(event.locationInWindow, from: nil)) }
    override func cursorUpdate(with event: NSEvent) { showCursor(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { NSCursor.setHiddenUntilMouseMoves(false) }
    private func showCursor(at point: CGPoint) {
        guard resize == nil, turn == nil else { return }
        guard atBox(point) else {
            NSCursor.setHiddenUntilMouseMoves(false)
            NSCursor.arrow.set()
            return
        }
        guard canvas?.session.colorPicker == nil else { return }
        if let corner = rotationCorner(at: point) {
            TextRotationCursor.cursor(degrees: TextRotationCursor.degrees(
                corner: corner, boxRotation: shownTransform?.rotation ?? 0)).set()
            return
        }
        guard let index = handle(at: point) else { NSCursor.iBeam.set(); return }
        handleCursor(index).set()
    }
    /// The box, its resize band, and the rotation zone around its corners.
    private func atBox(_ point: CGPoint) -> Bool {
        bounds.insetBy(dx: -edgeReach, dy: -edgeReach).contains(point) || rotates(at: point)
    }

    /// Every mouse move while the box is open, wherever the pointer is. Tracking areas stop arriving once the text
    /// surface has the mouse, which left the cursor stuck on whatever it was last set to. Inside the box it's the
    /// I-beam or a resize arrow, just outside a corner the rotation cursor; over the rest of the canvas, the Type
    /// tool's I-beam; leaving the canvas, the arrow, set once on the way out so the toolbar's own controls keep
    /// their cursors.
    private var moveMonitor: Any?
    private var pointerOnCanvas = true
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let moveMonitor { NSEvent.removeMonitor(moveMonitor); self.moveMonitor = nil }
        guard window != nil else { return }
        moveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self, self.window === event.window else { return event }
            self.pointerMoved(event)
            return event
        }
    }
    deinit {
        if let moveMonitor { NSEvent.removeMonitor(moveMonitor) }
    }
    func pointerMoved(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if atBox(point) {
            pointerOnCanvas = true
            showCursor(at: point)
        } else if let canvas, canvas.bounds.contains(canvas.convert(event.locationInWindow, from: nil)) {
            pointerOnCanvas = true
            guard resize == nil, turn == nil, canvas.session.colorPicker == nil else { return }
            NSCursor.iBeam.set()
        } else if pointerOnCanvas {
            pointerOnCanvas = false
            NSCursor.setHiddenUntilMouseMoves(false)
            NSCursor.arrow.set()
        }
    }

    /// The arrows for the edge or corner a handle resizes, turned with the text box.
    private func handleCursor(_ index: Int) -> NSCursor {
        let positions: [NSCursor.FrameResizePosition] = [.topLeft, .top, .topRight, .right, .topLeft, .top, .topRight, .right]
        // What is on screen: a new point text box has no transform in its draft until it is turned or resized.
        let rotation = shownTransform?.rotation ?? 0
        let turns = (Int((rotation / 45).rounded()) % 8 + 8) % 8
        let ordered: [NSCursor.FrameResizePosition] = [.topLeft, .top, .topRight, .right]
        let position = ordered[(ordered.firstIndex(of: positions[index])! + turns) % 4]
        return .frameResize(position: position, directions: [.inward, .outward])
    }

    /// How far either side of an edge counts as that edge, in the box's own units. Capped so a small box keeps a
    /// middle to type in.
    /// The Move tool's box grabs within 10 screen points of an edge; the handles here are drawn 6 points across, so
    /// the same reach is 10/6 of one.
    private var edgeReach: CGFloat { min(handleSize * 10 / 6, min(bounds.width, bounds.height) / 3) }

    /// How far past the resize band a corner still turns the box: 20 screen points, in the box's own units like the
    /// band's reach.
    private var rotationReach: CGFloat { handleSize * 20 / 6 }

    /// Just outside a corner, past the resize band: where a drag turns the box instead of resizing it. Only the
    /// corners, so beside an edge's middle, or farther out, the pointer is on the canvas.
    private func rotates(at point: CGPoint) -> Bool {
        rotationCorner(at: point) != nil
    }

    /// Share the nearest unit corner between hit testing and the cursor so overlapping zones agree.
    private func rotationCorner(at point: CGPoint) -> CGPoint? {
        guard handle(at: point) == nil, !bounds.contains(point) else { return nil }
        let corner = CGPoint(x: point.x < bounds.midX ? 0 : 1, y: point.y < bounds.midY ? 0 : 1)
        let position = CGPoint(x: bounds.minX + corner.x * bounds.width,
                               y: bounds.minY + corner.y * bounds.height)
        let reach = edgeReach + rotationReach
        return hypot(point.x - position.x, point.y - position.y) <= reach ? corner : nil
    }

    /// The edge or corner at a point, in handle order: a band along each edge, as the Move tool's box has, rather
    /// than only the handle squares. Nil anywhere else, which is the text.
    private func handle(at point: CGPoint) -> Int? {
        let reach = edgeReach
        let left = point.x <= reach, right = point.x >= bounds.width - reach
        let top = point.y <= reach, bottom = point.y >= bounds.height - reach
        guard point.x >= -reach, point.x <= bounds.width + reach,
              point.y >= -reach, point.y <= bounds.height + reach else { return nil }
        switch (left, right, top, bottom) {
        case (true, _, true, _): return 0
        case (_, true, true, _): return 2
        case (_, true, _, true): return 4
        case (true, _, _, true): return 6
        case (_, _, true, _): return 1
        case (_, true, _, _): return 3
        case (_, _, _, true): return 5
        case (true, _, _, _): return 7
        default: return nil
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if canvas?.session.colorPicker != nil { return nil }
        let local = convert(point, from: superview)
        if handle(at: local) != nil || rotates(at: local) { return self }
        return super.hitTest(point)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setStroke()
        let box = NSBezierPath(rect: bounds.insetBy(dx: handleSize / 12, dy: handleSize / 12))
        box.lineWidth = handleSize / 6
        box.stroke()
        for unit in LayerTransform.handles {
            let rect = CGRect(x: unit.x * bounds.width - handleSize / 2, y: unit.y * bounds.height - handleSize / 2,
                              width: handleSize, height: handleSize)
            NSColor.white.setFill(); rect.fill()
            NSColor.controlAccentColor.setStroke(); NSBezierPath(rect: rect).stroke()
        }
        // Text that doesn't fit is marked by a plus drawn in the bottom-right handle, as in Photoshop.
        if let container = textView.textContainer, let layout = textView.layoutManager {
            layout.ensureLayout(for: container)
            let range = layout.glyphRange(for: container)
            if NSMaxRange(range) < layout.numberOfGlyphs {
                let unit = LayerTransform.handles[4]
                let center = CGPoint(x: unit.x * bounds.width, y: unit.y * bounds.height)
                let arm = handleSize * 0.42
                let plus = NSBezierPath()
                plus.move(to: CGPoint(x: center.x - arm, y: center.y)); plus.line(to: CGPoint(x: center.x + arm, y: center.y))
                plus.move(to: CGPoint(x: center.x, y: center.y - arm)); plus.line(to: CGPoint(x: center.x, y: center.y + arm))
                plus.lineWidth = handleSize / 6
                NSColor.black.setStroke()
                plus.stroke()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let canvas, let document = canvas.session.document, let draft = canvas.session.textDraft else { return }
        let local = convert(event.locationInWindow, from: nil)
        let transform = shownTransform ?? draft.transform ?? LayerTransform(origin: draft.origin, size: logicalSize)
        let pixel = canvas.session.viewport.documentPoint(from: canvas.convert(event.locationInWindow, from: nil), documentSize: document.size)
        guard let handle = handle(at: local) else {
            if let corner = rotationCorner(at: local) {
                turn = (TransformDrag(original: transform, start: pixel, mode: .rotate), draft, corner)
                TextRotationCursor.cursor(degrees: TextRotationCursor.degrees(
                    corner: corner, boxRotation: shownTransform?.rotation ?? 0)).set()
            }
            return
        }
        // Dragging a handle turns point text into a box of the size it has right now, which then holds the text and
        // wraps it, rather than scaling the text. Its scale and rotation are whatever the layer already had.
        var fixed = draft
        if fixed.style.boxSize == nil {
            fixed.style.boxSize = logicalSize
            fixed.transform = transform
            fixed.origin = transform.origin
            canvas.session.textDraft = fixed
        }
        resize = (handle, fixed, transform, pixel)
    }
    override func mouseDragged(with event: NSEvent) {
        if turn != nil { turnBox(with: event); return }
        guard let resize, let canvas, let document = canvas.session.document else { return }
        let point = canvas.session.viewport.documentPoint(from: canvas.convert(event.locationInWindow, from: nil), documentSize: document.size)
        let old = resize.transform
        let dx = point.x - resize.start.x, dy = point.y - resize.start.y
        let localX = dx * cos(old.radians) + dy * sin(old.radians)
        let localY = -dx * sin(old.radians) + dy * cos(old.radians)
        let unit = LayerTransform.handles[resize.handle]
        var left: CGFloat = 0, top: CGFloat = 0, right = old.size.width, bottom = old.size.height
        let source = resize.draft.style.boxSize ?? logicalSize
        let minW = 16 * old.size.width / source.width, minH = 16 * old.size.height / source.height
        if unit.x == 0 { left = min(localX, right - minW) }
        if unit.x == 1 { right = max(left + minW, right + localX) }
        if unit.y == 0 { top = min(localY, bottom - minH) }
        if unit.y == 1 { bottom = max(top + minH, bottom + localY) }
        var draft = resize.draft
        draft.style.boxSize = CGSize(width: ((right - left) * source.width / old.size.width).rounded(),
                                     height: ((bottom - top) * source.height / old.size.height).rounded())
        guard draft.style.boxIsValid else { return }
        var transform = old
        transform.size = CGSize(width: draft.style.boxSize!.width * old.size.width / source.width,
                                height: draft.style.boxSize!.height * old.size.height / source.height)
        let anchor = old.point(CGPoint(x: left / old.size.width, y: top / old.size.height))
        let current = transform.point(.zero)
        transform.origin.x += anchor.x - current.x
        transform.origin.y += anchor.y - current.y
        guard transform.isValid else { return }
        draft.origin = transform.origin
        draft.transform = transform
        canvas.session.textDraft = draft
        canvas.synchronizeDisplay()
    }
    /// Turns the box about its center, whole degrees, Shift in steps of 15. The rotation lives in the draft like a
    /// resize does, so it commits and cancels with the edit.
    private func turnBox(with event: NSEvent) {
        guard let turn, let canvas, let document = canvas.session.document else { return }
        let point = canvas.session.viewport.documentPoint(from: canvas.convert(event.locationInWindow, from: nil), documentSize: document.size)
        var rotated = turn.drag.updated(to: point, lockRatio: false, shift: event.modifierFlags.contains(.shift))
        let start = turn.drag.original.rotation
        // Keep the shortest turn from the starting angle because the Type bar's angle field shows this value.
        rotated.rotation = start + remainder(rotated.rotation - start, 360)
        rotated.rotation = rotated.rotation.rounded()
        guard rotated.isValid else { return }
        var draft = turn.draft
        draft.place(rotated, size: logicalSize)
        canvas.session.textDraft = draft
        canvas.synchronizeDisplay()
        TextRotationCursor.cursor(degrees: TextRotationCursor.degrees(
            corner: turn.corner, boxRotation: shownTransform?.rotation ?? rotated.rotation)).set()
    }
    override func mouseUp(with event: NSEvent) { resize = nil; turn = nil; window?.makeFirstResponder(textView) }
}

extension CanvasView {
    func synchronizeInlineText() {
        guard let draft = session.textDraft else {
            if inlineTextEditor != nil {
                let hadFocus = window?.firstResponder === inlineTextEditor?.textView
                inlineTextEditor?.removeFromSuperview()
                inlineTextEditor = nil
                needsDisplay = true
                if hadFocus { window?.makeFirstResponder(self) }
            }
            return
        }
        if inlineTextEditor?.draftID != draft.id { needsDisplay = true }
        if inlineTextEditor == nil {
            let editor = InlineTextEditor(canvas: self)
            inlineTextEditor = editor
            addSubview(editor)
            needsDisplay = true
        }
        inlineTextEditor?.synchronize(draft)
    }

    func beginTextGesture(at point: CGPoint, event: NSEvent) {
        guard let document = session.document, session.finishText() else { return }
        let pixel = session.viewport.documentPoint(from: point, documentSize: document.size)
        let visible = document.effectiveVisibleIDs
        if let layer = document.layers.reversed().first(where: { visible.contains($0.id) && $0.liveText != nil && $0.transform.contains(pixel) }) {
            session.selectLayer(layer.id)
            session.editActiveText()
            synchronizeInlineText()
            inlineTextEditor?.textView.mouseDown(with: event)
        } else {
            textBoxAnchor = pixel
            textBoxRect = CGRect(origin: pixel, size: .zero)
        }
        needsDisplay = true
    }

    func dragTextGesture(to point: CGPoint) {
        guard let anchor = textBoxAnchor, let document = session.document else { return }
        let pixel = session.viewport.documentPoint(from: point, documentSize: document.size)
        textBoxRect = DragBox.rect(from: anchor, to: pixel, square: false, fromCenter: false)
        needsDisplay = true
    }

    func finishTextGesture() {
        guard let rect = textBoxRect else { return }
        textBoxAnchor = nil; textBoxRect = nil
        if rect.width < 4 && rect.height < 4 { session.beginText(at: rect.origin, newLayer: true) }
        else { session.beginText(in: rect) }
        synchronizeInlineText()
        needsDisplay = true
    }

    func drawTextBoxDraft() {
        guard let rect = textBoxRect, let document = session.document else { return }
        let origin = session.viewport.viewPoint(from: rect.origin, documentSize: document.size)
        let scale = session.viewport.pointsPerPixel
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: CGRect(origin: origin, size: CGSize(width: rect.width * scale, height: rect.height * scale)))
        path.lineWidth = 1
        path.stroke()
    }
}
