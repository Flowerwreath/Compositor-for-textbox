import AppKit
import SwiftUI
import Testing
@testable import Compositor

@MainActor
struct TypeToolTests {
    private final class TextEditingWindow: NSWindow {
        // The test host runs in the background. Give AppKit a key-window condition without stealing user focus.
        override var isKeyWindow: Bool { true }
    }
    private func makeSession() -> EditorSession {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600, emptyLayer: true)
        session.selectTool(.type)
        return session
    }

    private func beginEditingText(in session: EditorSession) {
        session.beginText(at: CGPoint(x: 100, y: 100))
        session.textDraft?.style.content = "Editing"
    }

    @Test func createEditCancelAndUndo() throws {
        let session = makeSession()
        let before = session.history.undoCount
        session.beginText(at: CGPoint(x: 30, y: 40))
        // A click starts the first letter on the pointer: the box sits its padding to the left and its first
        // baseline's height above.
        let start = try #require(session.textDraft)
        let style = start.style
        let descent = abs((EditorSession.textAttributes(style)[.font] as? NSFont)?.descender ?? 0)
        #expect(start.origin == CGPoint(x: 30 - LayerTextStyle.padding, y: 40 - (LayerTextStyle.padding + style.lineHeight - descent)))
        session.textDraft?.style.content = "Text"
        #expect(session.document?.layers.count == 1)
        var draft = try #require(session.textDraft)
        draft.style.content = "Hello\nCompositor"
        draft.style.fontSize = 48
        #expect(session.applyText(draft))
        #expect(session.activeLayer?.liveText?.style == draft.style)
        #expect(session.activeLayer?.origin == start.origin)
        #expect(session.history.undoCount == before + 1)
        session.editActiveText()
        session.textDraft = nil
        #expect(session.history.undoCount == before + 1)
        session.editActiveText()
        draft = try #require(session.textDraft)
        draft.style.content = "Changed"
        #expect(session.applyText(draft))
        session.undo()
        #expect(session.activeLayer?.liveText?.style.content == "Hello\nCompositor")
        session.undo()
        #expect(session.document?.layers.count == 1)
        session.redo()
        #expect(session.activeLayer?.liveText != nil)
    }

    @Test func textColorPickerPreviewsAndRestoresDraft() throws {
        let session = makeSession()
        session.beginText(at: CGPoint(x: 30, y: 40))
        let original = try #require(session.textDraft?.style)

        session.openTextColorPicker()
        try #require(session.colorPicker).hsb.setRGB(PaletteColor(red: 1, green: 0, blue: 0))
        session.previewTextColor()
        #expect(session.textDraft?.style.red == 1)
        #expect(session.textDraft?.style.green == 0)
        #expect(session.foregroundColor == .black)

        session.closeColorPicker(commit: false)
        #expect(session.textDraft?.style == original)
        #expect(session.foregroundColor == .black)

        session.openTextColorPicker()
        try #require(session.colorPicker).hsb.setRGB(PaletteColor(red: 0, green: 0, blue: 1))
        session.previewTextColor()
        session.closeColorPicker(commit: true)
        #expect(session.textDraft?.style.blue == 1)
        #expect(session.foregroundColor == PaletteColor(red: 0, green: 0, blue: 1))
    }

    @Test func transformsDuplicatesAndClippingKeepTextEditable() throws {
        let session = makeSession()
        session.beginText(at: CGPoint(x: 20, y: 20))
        session.textDraft?.style.content = "Text"
        #expect(session.applyText(try #require(session.textDraft)))
        let id = try #require(session.activeLayerID)
        let index = try #require(session.document?.layers.firstIndex(where: { $0.id == id }))
        session.document?.layers[index].transform.rotation = 30
        session.document?.layers[index].transform.size.width *= 2
        let old = try #require(session.activeLayer?.transform)
        session.editActiveText()
        var draft = try #require(session.textDraft)
        draft.style.content = "Longer text"
        #expect(session.applyText(draft))
        let updated = try #require(session.activeLayer?.transform)
        #expect(updated.rotation == 30)
        #expect(abs(updated.point(.zero).x - old.point(.zero).x) < 0.001)
        #expect(abs(updated.point(.zero).y - old.point(.zero).y) < 0.001)
        session.duplicateActiveLayer()
        #expect(session.activeLayer?.liveText?.style.content == "Longer text")
        let target = try #require(session.activeLayerID)
        #expect(session.linkMask(source: id, target: target))
        #expect(session.activeLayer?.maskSourceID == id)
        #expect(session.document?.layers.first(where: { $0.id == id })?.liveText != nil)
    }

    @Test func saveReopenAndRasterize() async throws {
        let session = makeSession()
        session.beginText(at: .zero)
        session.textDraft?.style.content = "Text"
        var draft = try #require(session.textDraft)
        draft.style.content = "Café 日本語\nSecond line"
        draft.style.alignment = .right
        draft.style.tracking = 3
        #expect(session.applyText(draft))
        let snapshot = try #require(session.projectSnapshot())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".compositor")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(snapshot, to: url)
        let loaded = try await ProjectStore.shared.load(from: url)
        let reopened = makeSession()
        reopened.installProject(loaded, from: url)
        #expect(reopened.activeLayer?.liveText?.style == draft.style)
        let index = try #require(reopened.document?.layers.firstIndex(where: { $0.id == reopened.activeLayerID }))
        let replacement = try EditorSession.shapeImage(.rectangle, size: CGSize(width: 10, height: 10), color: PaletteColor(red: 1, green: 0, blue: 0))
        reopened.document?.layers[index].asset = ImportedImage(image: replacement, thumbnail: replacement, name: "Painted")
        #expect(reopened.activeLayer?.liveText == nil)
        #expect(reopened.projectSnapshot()?.manifest.layers[index].text == nil)
    }

    @Test func rasterHasTransparentBackgroundAndColoredGlyphs() throws {
        var style = LayerTextStyle()
        style.content = "TYPE"
        style.red = 1
        let image = try EditorSession.textImage(style)
        let bytes = try #require(image.dataProvider?.data) as Data
        var ink = 0, clear = 0
        for i in stride(from: 0, to: bytes.count - 3, by: 4) {
            if bytes[i + 3] == 0 { clear += 1 }
            else { ink += 1; #expect(bytes[i] > 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0) }
        }
        #expect(ink > 100 && clear > 100)
    }

    @Test func clippingToTextExportsColoredGlyphsOnTransparency() async throws {
        let session = makeSession()
        session.beginText(at: .zero)
        // The box on the canvas's corner, where the clipped fill below is placed.
        session.textDraft?.origin = .zero
        session.textDraft?.style.content = "Text"
        #expect(session.applyText(try #require(session.textDraft)))
        let source = try #require(session.activeLayerID)
        let size = try #require(session.activeLayer?.size)
        let fill = try EditorSession.shapeImage(.rectangle, size: size, color: PaletteColor(red: 1, green: 0, blue: 0))
        session.addPixelLayer(fill, at: .zero, name: "Clipped color", editName: "Fill")
        #expect(session.linkMask(source: source, target: try #require(session.activeLayerID)))
        let exported = try await ImageExporter.shared.render(try #require(session.projectSnapshot())).image
        let context = try #require(CGContext(data: nil, width: exported.width, height: exported.height,
            bitsPerComponent: 8, bytesPerRow: exported.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(exported, in: CGRect(x: 0, y: 0, width: exported.width, height: exported.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var ink = 0, clear = 0
        for i in stride(from: 0, to: exported.width * exported.height * 4, by: 4) {
            if bytes[i + 3] == 0 { clear += 1 }
            else if bytes[i + 3] == 255 { ink += 1; #expect(bytes[i] == 255 && bytes[i + 1] == 0) }
        }
        #expect(ink > 100 && clear > 100)
    }

    @Test func paragraphBoxAndToolSwitchCommitEditableText() throws {
        let session = makeSession()
        session.beginText(in: CGRect(x: 40, y: 60, width: 200, height: 120))
        #expect(session.textDraft?.style.content == "")
        session.textDraft?.style.content = "Text that wraps inside its paragraph box"
        session.selectTool(.brush)
        #expect(session.textDraft == nil && session.tool == .brush)
        #expect(session.activeLayer?.size == CGSize(width: 200, height: 120))
        #expect(session.activeLayer?.liveText?.style.boxSize == CGSize(width: 200, height: 120))
        session.selectTool(.type)
        session.editActiveText()
        session.textDraft?.style.content = "Edited on canvas"
        session.cancelText()
        #expect(session.activeLayer?.liveText?.style.content == "Text that wraps inside its paragraph box")
    }

    @Test func emptyNewParagraphIsDiscarded() {
        let session = makeSession()
        let count = session.document?.layers.count
        session.beginText(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        session.selectTool(.brush)
        #expect(session.document?.layers.count == count)
        #expect(session.textDraft == nil)
    }

    @Test func closeButtonShouldCloseWindowWhileEditingText() async throws {
        let workspace = ProjectWorkspace()
        let session = workspace.current.session
        session.createDocument(width: 800, height: 600, emptyLayer: true)
        session.selectTool(.type)
        beginEditingText(in: session)

        let bridge = ProjectWindowView(controller: workspace.current.controller)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = bridge
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(50))

        window.standardWindowButton(.closeButton)?.performClick(nil)
        var alertWindow: NSWindow?
        for _ in 0..<20 where alertWindow == nil {
            alertWindow = window.attachedSheet
            if alertWindow == nil { try await Task.sleep(for: .milliseconds(10)) }
        }
        let sheet = try #require(alertWindow)
        func button(in view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.title == "Don’t Save" { return button }
            for child in view.subviews {
                if let button = button(in: child) { return button }
            }
            return nil
        }
        let contentView = try #require(sheet.contentView)
        let discard = try #require(button(in: contentView))
        discard.performClick(nil)
        try await Task.sleep(for: .milliseconds(50))

        #expect(!window.isVisible)
        #expect(session.textDraft == nil)
    }

    @Test func commandQShouldTerminateWhileEditingText() async throws {
        let delegate = CompositorApplicationDelegate()
        let session = delegate.session
        session.createDocument(width: 800, height: 600, emptyLayer: true)
        session.selectTool(.type)
        beginEditingText(in: session)

        let bridge = ProjectWindowView(controller: delegate.projects)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = bridge
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(50))

        delegate.workspace.window = window
        delegate.projects.window = window
        let quitTask = Task { await delegate.workspace.confirmQuit() }
        var alertWindow: NSWindow?
        for _ in 0..<20 where alertWindow == nil {
            alertWindow = window.attachedSheet
            if alertWindow == nil { try await Task.sleep(for: .milliseconds(10)) }
        }
        let sheet = try #require(alertWindow)
        func button(in view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.title == "Don’t Save" { return button }
            for child in view.subviews {
                if let button = button(in: child) { return button }
            }
            return nil
        }
        let contentView = try #require(sheet.contentView)
        let discard = try #require(button(in: contentView))
        discard.performClick(nil)
        #expect(await quitTask.value)

        #expect(window.attachedSheet == nil)
        #expect(session.textDraft == nil)
    }

    /// While text is open, the Type tool keeps its I-beam over the canvas, and the pointer goes back to the arrow, shown
    /// again, once it leaves the canvas for the toolbar. Tested on the view alone: no second window in the test host.
    @Test func theCursorFollowsThePointerWhileEditingText() throws {
        let session = makeSession()
        session.beginText(at: CGPoint(x: 20, y: 20))
        let view = CanvasView(session: session)
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        view.synchronizeDisplay()
        let editor = try #require(view.inlineTextEditor)
        func move(to point: NSPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                            context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        }
        defer { NSCursor.arrow.set() }

        NSCursor.arrow.set()
        editor.pointerMoved(try move(to: NSPoint(x: 780, y: 580)))
        #expect(NSCursor.current === NSCursor.iBeam, "over the canvas, away from the box, the Type tool's I-beam")

        NSCursor.setHiddenUntilMouseMoves(true)
        editor.pointerMoved(try move(to: NSPoint(x: -10, y: -10)))
        #expect(NSCursor.current === NSCursor.arrow, "off the canvas, the arrow")
    }

    @Test func invalidAndStaleDraftsDoNotChangeDocument() throws {
        let session = makeSession()
        session.beginText(at: .zero)
        session.textDraft?.style.content = "Text"
        var draft = try #require(session.textDraft)
        draft.style.fontSize = .nan
        #expect(!session.applyText(draft))
        draft.style.fontSize = 72
        draft.style.boxSize = CGSize(width: 0, height: 100)
        #expect(!session.applyText(draft))
        draft.style.boxSize = CGSize(width: 360, height: 160)
        draft.style.content = "Valid"
        session.textDraft = nil
        session.createDocument(width: 100, height: 100, emptyLayer: true)
        #expect(!session.applyText(draft))
        #expect(session.document?.layers.count == 1)
    }

    /// Zoomed in, text being typed shows as the pixels it will be committed as, so confirming it changes nothing on
    /// screen — at a zoom that smooths pixels and at one that shows them hard-edged.
    @Test(arguments: [1.5, 4] as [CGFloat])
    func textLooksTheSameWhileEditingAndOnceCommitted(zoom: CGFloat) throws {
        let session = makeSession()
        let view = CanvasView(session: session)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        session.viewport.resize(to: view.bounds.size, backingScale: 1, documentSize: CGSize(width: 800, height: 600))
        session.zoom(to: zoom)
        func snapshot() throws -> [UInt8] {
            // The canvas's own drawing, without the editor's box and handles over it.
            view.synchronizeDisplay()
            view.subviews.forEach { $0.isHidden = true }
            defer { view.subviews.forEach { $0.isHidden = false } }
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let data = try #require(rep.bitmapData)
            return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
        }
        let blank = try snapshot()
        session.beginText(at: CGPoint(x: 380, y: 300))
        session.textDraft?.style.content = "Sharp"
        session.textDraft?.style.fontSize = 24
        view.synchronizeDisplay()
        let editor = try #require(view.inlineTextEditor)
        #expect(editor.textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .clear)

        let editing = try snapshot()
        #expect(editing != blank, "the text being typed wasn't drawn on the canvas")
        #expect(session.finishText())
        #expect(session.activeLayer?.liveText != nil)
        let committed = try snapshot()
        #expect(editing.count == committed.count)
        let largest = zip(editing, committed).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(largest <= 2, "the canvas changed by up to \(largest) when the text was committed")
    }

    /// Kanji, kana and whatever else an input method is still composing show on the canvas as they are typed, not
    /// only once Return commits them: the editor's own letters are clear, so the draft has to hold them.
    @Test func textBeingComposedShowsOnTheCanvas() throws {
        let session = makeSession()
        let view = CanvasView(session: session)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        session.viewport.resize(to: view.bounds.size, backingScale: 1, documentSize: CGSize(width: 800, height: 600))
        func snapshot() throws -> [UInt8] {
            view.synchronizeDisplay()
            view.subviews.forEach { $0.isHidden = true }
            defer { view.subviews.forEach { $0.isHidden = false } }
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let data = try #require(rep.bitmapData)
            return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
        }
        session.beginText(at: CGPoint(x: 100, y: 300))
        session.textDraft?.style.content = "abc"
        view.synchronizeDisplay()
        let textView = try #require(view.inlineTextEditor?.textView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        let typed = try snapshot()
        let none = NSRange(location: NSNotFound, length: 0)

        textView.setMarkedText("まみ", selectedRange: NSRange(location: 2, length: 0), replacementRange: none)
        #expect(textView.hasMarkedText())
        #expect(session.textDraft?.style.content == "abcまみ")
        #expect(try snapshot() != typed, "the letters being composed weren't drawn on the canvas")

        textView.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: none)
        #expect(session.textDraft?.style.content == "abc", "a composition given up leaves nothing behind")

        textView.setMarkedText("まみ", selectedRange: NSRange(location: 2, length: 0), replacementRange: none)
        textView.insertText("真美", replacementRange: none)
        #expect(!textView.hasMarkedText())
        #expect(session.textDraft?.style.content == "abc真美")
    }

    /// Esc while an input method is composing is the input method's: it gives up the conversion, and the text box
    /// stays open. Only an Esc with nothing being composed closes the box.
    @Test func escapeWhileComposingGivesUpTheCompositionNotTheTextBox() throws {
        let session = makeSession()
        let view = CanvasView(session: session)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        session.viewport.resize(to: view.bounds.size, backingScale: 1, documentSize: CGSize(width: 800, height: 600))
        session.beginText(at: CGPoint(x: 100, y: 300))
        session.textDraft?.style.content = "abc"
        view.synchronizeDisplay()
        let textView = try #require(view.inlineTextEditor?.textView)
        // Keys reach the input method only from the text being edited.
        #expect(window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                                   charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))

        textView.setMarkedText("まみ", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(textView.hasMarkedText())
        textView.keyDown(with: escape)
        #expect(session.textDraft != nil, "Esc while composing closed the text box")
        #expect(session.textDraft?.style.content == "abc", "what was being composed wasn't given up")
        #expect(!textView.hasMarkedText())

        textView.keyDown(with: escape)
        #expect(session.textDraft == nil, "with nothing being composed, Esc closes the text box")
    }

    private let red = PaletteColor(red: 1, green: 0, blue: 0)

    @Test func colorAppliesToSelectionAndFollowsEdits() {
        var style = LayerTextStyle()
        style.content = "Hello world"
        style.setColor(red, in: NSRange(location: 6, length: 5))
        #expect(style.colorRuns == [LayerTextColorRun(location: 6, length: 5, red: 1, green: 0, blue: 0)])
        #expect(style.color(at: 5) == .black && style.color(at: 6) == red)
        // Painting next to a run in the same color joins it.
        style.setColor(red, in: NSRange(location: 5, length: 1))
        #expect(style.colorRuns?.count == 1 && style.colorRuns?.first?.location == 5)

        // Typed letters take the color of the one before them; deleted ones take their color away.
        style.replaceCharacters(in: NSRange(location: 11, length: 0), withLength: 1)
        style.content += "!"
        #expect(style.isValid && style.color(at: 11) == red)
        style.replaceCharacters(in: NSRange(location: 0, length: 2), withLength: 0)
        style.content.removeFirst(2)
        #expect(style.isValid && style.colorRuns?.first?.location == 3 && style.colorRuns?.first?.length == 7)

        // No selection, or all of it, recolors the whole text.
        style.setColor(red, in: NSRange(location: 4, length: 0))
        #expect(style.colorRuns == nil && style.red == 1)
    }

    @Test func invalidColorRunsAreRejected() {
        var style = LayerTextStyle()
        style.content = "Text"
        style.colorRuns = [LayerTextColorRun(location: 2, length: 3, red: 1, green: 0, blue: 0)]
        #expect(!style.isValid)
        style.colorRuns = [LayerTextColorRun(location: 0, length: 2, red: 1, green: 0, blue: 0),
                           LayerTextColorRun(location: 1, length: 2, red: 0, green: 1, blue: 0)]
        #expect(!style.isValid)
        style.colorRuns = [LayerTextColorRun(location: 0, length: 1, red: 2, green: 0, blue: 0)]
        #expect(!style.isValid)
    }

    /// Opaque pixels of `image` that are mostly red, and those that are dark.
    private func redAndDarkPixels(_ image: CGImage) -> (red: Int, dark: Int) {
        let rep = NSBitmapImageRep(cgImage: image)
        var red = 0, dark = 0
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.9 else { continue }
            if color.redComponent > 0.8, color.greenComponent < 0.2 { red += 1 }
            else if color.redComponent < 0.2 { dark += 1 }
        } }
        return (red, dark)
    }

    @Test func selectedColorPaintsOnlyThoseLettersAndSurvivesReopening() async throws {
        let session = makeSession()
        session.beginText(at: CGPoint(x: 30, y: 40))
        session.textDraft?.style.content = "AAAA BBBB"
        session.textDraft?.selection = NSRange(location: 5, length: 4)
        session.openTextColorPicker()
        try #require(session.colorPicker).hsb.setRGB(red)
        session.previewTextColor()
        session.closeColorPicker(commit: true)
        #expect(session.textDraft?.style.red == 0, "the letters outside the selection changed color")
        #expect(session.textDraft?.style.color(at: 5) == red)
        #expect(session.finishText())
        let image = try #require(session.activeLayer?.asset?.image)
        let pixels = redAndDarkPixels(image)
        #expect(pixels.red > 50 && pixels.dark > 50)

        let snapshot = try #require(session.projectSnapshot())
        #expect(snapshot.manifest.version == 12)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TextColors-\(UUID()).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(snapshot, to: url)
        let reopened = EditorSession()
        reopened.installProject(try await ProjectStore.shared.load(from: url), from: url)
        let text = try #require(reopened.document?.layers.last?.liveText)
        #expect(text.style == session.activeLayer?.liveText?.style)
        #expect(redAndDarkPixels(text.image) == pixels)

        var legacy = snapshot.manifest
        legacy.version = 9
        try JSONEncoder().encode(legacy).write(to: url.appendingPathComponent("manifest.json"))
        do {
            _ = try await ProjectStore.shared.load(from: url)
            Issue.record("Version 9 with color runs should be rejected")
        } catch ProjectError.invalid {}

        session.undo()
        #expect(session.activeLayer?.liveText == nil)

        legacy.version = 10
        let textIndex = try #require(legacy.layers.firstIndex { $0.text != nil })
        legacy.layers[textIndex].text?.fontRuns = [LayerTextFontRun(location: 0, length: 1, fontName: "Courier")]
        try JSONEncoder().encode(legacy).write(to: url.appendingPathComponent("manifest.json"))
        do {
            _ = try await ProjectStore.shared.load(from: url)
            Issue.record("Version 10 with font runs should be rejected")
        } catch ProjectError.invalid {}
    }

    @Test func fontAppliesToTheSelectionOnly() {
        var style = LayerTextStyle()
        style.content = "Hello"
        style.fontName = "Helvetica"
        style.setFont("Courier", in: NSRange(location: 0, length: 2))
        #expect(style.fontName == "Helvetica")
        #expect(style.fontRuns == [LayerTextFontRun(location: 0, length: 2, fontName: "Courier")])
        #expect(style.fontName(at: 0) == "Courier" && style.fontName(at: 2) == "Helvetica")
        #expect(style.uniformFontName(in: NSRange(location: 0, length: 2)) == "Courier")
        #expect(style.uniformFontName(in: NSRange(location: 0, length: 5)) == nil)
        style.setFont("Courier", in: NSRange(location: 0, length: 5))
        #expect(style.fontRuns == nil && style.fontName == "Courier")
        style.setFont("Helvetica", in: NSRange(location: 0, length: 2))
        #expect(style.fontRuns == [LayerTextFontRun(location: 0, length: 2, fontName: "Helvetica")])
        style.setFont("Courier", in: NSRange(location: 0, length: 0))
        #expect(style.fontRuns == nil && style.fontName == "Courier")
        style.setFont("Helvetica", in: NSRange(location: 1, length: 3))
        style.replaceCharacters(in: NSRange(location: 5, length: 0), withLength: 1)
        style.content += "!"
        #expect(style.isValid && style.fontName(at: 5) == "Courier")
    }

    @Test func selectedFontSurvivesReopening() async throws {
        let session = makeSession()
        session.beginText(at: CGPoint(x: 30, y: 40))
        session.textDraft?.style.content = "Hello"
        session.textDraft?.style.fontName = "Helvetica"
        session.textDraft?.selection = NSRange(location: 0, length: 2)
        session.changeTextStyle { $0.setFont("Courier", in: session.textDraft?.selection ?? NSRange()) }
        #expect(session.finishText())
        let snapshot = try #require(session.projectSnapshot())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TextFonts-\(UUID()).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(snapshot, to: url)
        let reopened = EditorSession()
        reopened.installProject(try await ProjectStore.shared.load(from: url), from: url)
        let text = try #require(reopened.document?.layers.last?.liveText)
        #expect(text.style.fontRuns == [LayerTextFontRun(location: 0, length: 2, fontName: "Courier")])
        #expect(text.style.fontName == "Helvetica")
    }

    /// The top and bottom rows of `image` with any ink in them, across `columns` or the whole width.
    private func inkRows(_ image: CGImage, columns: Range<Int>? = nil) throws -> (top: Int, bottom: Int)? {
        let bytes = try #require(image.dataProvider?.data) as Data
        let columns = columns ?? 0..<image.width
        var top: Int?, bottom: Int?
        for y in 0..<image.height {
            for x in columns where bytes[y * image.bytesPerRow + x * 4 + 3] > 0 {
                if top == nil { top = y }
                bottom = y
                break
            }
        }
        guard let top, let bottom else { return nil }
        return (top, bottom)
    }

    /// The runs of columns of `image` with any ink in them, left to right.
    private func inkedColumns(_ image: CGImage) throws -> [Range<Int>] {
        let bytes = try #require(image.dataProvider?.data) as Data
        var runs: [Range<Int>] = [], start: Int?
        for x in 0...image.width {
            let inked = x < image.width && (0..<image.height).contains { bytes[$0 * image.bytesPerRow + x * 4 + 3] > 0 }
            if inked, start == nil { start = x }
            if !inked, let first = start { runs.append(first..<x); start = nil }
        }
        return runs
    }

    private func tallLetters(leading: CGFloat, content: String) -> LayerTextStyle {
        var style = LayerTextStyle()
        style.fontName = "Helvetica"
        style.fontSize = 200
        style.leading = leading
        style.content = content
        return style
    }

    private func textEditor(leading: CGFloat, content: String) throws -> (CanvasView, CanvasTextView) {
        let session = makeSession()
        session.textDefaults = tallLetters(leading: leading, content: "")
        session.beginText(at: CGPoint(x: 300, y: 300))
        session.textDraft?.style.content = content
        let canvas = CanvasView(session: session)
        canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        canvas.synchronizeDisplay()
        return (canvas, try #require(canvas.inlineTextEditor?.textView))
    }

    /// Capture the native editor at one pixel per text point; its clear letters leave only selection and caret.
    private func editorBitmap(_ view: NSView) throws -> NSBitmapImageRep {
        // AppKit places its insertion view after drawing the text; let that display pass finish before capture.
        view.displayIfNeeded()
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(view.bounds.width)),
            pixelsHigh: Int(ceil(view.bounds.height)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = view.bounds.size
        // A transparent view need not overwrite every pixel; never reuse uninitialized capture memory.
        try #require(bitmap.bitmapData).initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private func highlightedRows(_ bitmap: NSBitmapImageRep, x: Int) -> [Int] {
        (0..<bitmap.pixelsHigh).filter { (bitmap.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.05 }
    }

    private func caretRows(_ bitmap: NSBitmapImageRep) -> [Int] {
        (0..<bitmap.pixelsHigh).filter { y in
            (0..<bitmap.pixelsWide).contains { (bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.05 }
        }
    }

    @Test func selectionCoversTheLettersRegardlessOfLeading() throws {
        for leading: CGFloat in [10, 200, 0, 300] {
            let (canvas, textView) = try textEditor(leading: leading, content: "Hg\nHg")
            defer { withExtendedLifetime(canvas) {} }
            let layout = try #require(textView.layoutManager)
            layout.ensureLayout(for: try #require(textView.textContainer))
            let font = try #require(textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
            let bitmap = try editorBitmap(textView)
            let rows = highlightedRows(bitmap, x: 10)
            let baseline = textView.textContainerOrigin.y + layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY
                + layout.location(forGlyphAt: 0).y
            let bottom = baseline + leadingValue(leading) + abs(font.descender)
            #expect(abs(CGFloat(try #require(rows.first)) - (baseline - font.ascender)) <= 1, "leading \(leading): highlight top")
            #expect(abs(CGFloat(try #require(rows.last)) + 1 - bottom) <= 1, "leading \(leading): highlight bottom")
            let alphas = rows.compactMap { bitmap.colorAt(x: 10, y: $0)?.alphaComponent }
            #expect((alphas.max() ?? 0) - (alphas.min() ?? 0) < 0.02, "overlapping lines must not darken the selection")
            if leadingValue(leading) > font.ascender + abs(font.descender) {
                let gap = Int(baseline + abs(font.descender) + 2)
                #expect(!rows.contains(gap), "the space between lines must stay clear")
            }
        }
    }

    private func leadingValue(_ leading: CGFloat) -> CGFloat { leading == 0 ? 240 : leading }

    @Test func caretCoversTheLettersRegardlessOfLeading() throws {
        for leading: CGFloat in [10, 200, 0] {
            let (canvas, textView) = try textEditor(leading: leading, content: "Hg\nHg")
            let window = TextEditingWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = try #require(canvas.inlineTextEditor)
            defer { window.orderOut(nil) }
            #expect(window.makeFirstResponder(textView))
            for location in [1, 4, 5] {
                textView.setSelectedRange(NSRange(location: location, length: 0))
                textView.updateInsertionPointStateAndRestartTimer(true)
                let bitmap = try editorBitmap(textView)
                let layout = try #require(textView.layoutManager)
                let font = try #require(textView.typingAttributes[.font] as? NSFont)
                let glyph = layout.glyphIndexForCharacter(at: min(location, 4))
                let baseline = textView.textContainerOrigin.y + layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
                    + layout.location(forGlyphAt: glyph).y
                let rows = caretRows(bitmap)
                #expect(abs(CGFloat(try #require(rows.first)) - (baseline - font.ascender)) <= 1)
                #expect(abs(CGFloat(try #require(rows.last)) + 1 - (baseline + abs(font.descender))) <= 1)
            }
        }
    }

    @Test func anEmptyLinesCaretUsesTheTypingFont() throws {
        for leading: CGFloat in [10, 200, 0] {
            for content in ["", "Hg\n", "Hg\n\n", "Hg\r", "Hg\r\n", "Hg\u{2028}", "Hg\u{2029}"] {
                let (canvas, textView) = try textEditor(leading: leading, content: content)
                let window = TextEditingWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = try #require(canvas.inlineTextEditor)
                defer { window.orderOut(nil) }
                #expect(window.makeFirstResponder(textView))
                let font = try #require(NSFont(name: "Courier", size: 160))
                textView.setSelectedRange(NSRange(location: content.utf16.count, length: 0))
                textView.typingAttributes[.font] = font
                textView.updateInsertionPointStateAndRestartTimer(true)
                let bitmap = try editorBitmap(textView)
                let layout = try #require(textView.layoutManager)
                let bottom = textView.textContainerOrigin.y + layout.extraLineFragmentRect.maxY
                let rows = caretRows(bitmap)
                #expect(abs(CGFloat(try #require(rows.first)) - (bottom - font.ascender - abs(font.descender))) <= 1,
                        "leading \(leading), content \(content.debugDescription): empty line top")
                #expect(abs(CGFloat(try #require(rows.last)) + 1 - bottom) <= 1,
                        "leading \(leading), content \(content.debugDescription): empty line bottom")
            }
        }
    }

    @Test func selectionAndCaretFollowWrappedLinesAndFontRuns() throws {
        for leading: CGFloat in [10, 0, 120] {
            let (canvas, textView) = try textEditor(leading: leading, content: "HHHH HHHH HHHH")
            canvas.session.changeTextStyle {
                $0.fontSize = 48
                $0.boxSize = CGSize(width: 180, height: 400)
                $0.fontRuns = [LayerTextFontRun(location: 5, length: 4, fontName: "Courier")]
            }
            canvas.synchronizeDisplay()
            let window = TextEditingWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = try #require(canvas.inlineTextEditor)
            defer { window.orderOut(nil) }
            #expect(window.makeFirstResponder(textView))
            let layout = try #require(textView.layoutManager)
            layout.ensureLayout(for: try #require(textView.textContainer))
            let helvetica = try #require(NSFont(name: "Helvetica", size: 48))
            let courier = try #require(NSFont(name: "Courier", size: 48))
            var lines: [(range: NSRange, top: CGFloat, bottom: CGFloat)] = []
            layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { fragment, _, _, glyphs, _ in
                let range = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                let containsCourier = NSIntersectionRange(range, NSRange(location: 5, length: 4)).length > 0
                let containsHelvetica = range.length > NSIntersectionRange(range, NSRange(location: 5, length: 4)).length
                let faces = (containsCourier ? [courier] : []) + (containsHelvetica ? [helvetica] : [])
                let baseline = textView.textContainerOrigin.y + fragment.minY + layout.location(forGlyphAt: glyphs.location).y
                lines.append((range, baseline - (faces.map(\.ascender).max() ?? 0),
                              baseline + (faces.map { abs($0.descender) }.max() ?? 0)))
            }
            #expect(lines.count >= 3, "this exercises soft wrapping, not just explicit newlines")
            for line in lines {
                textView.setSelectedRange(line.range)
                let rows = highlightedRows(try editorBitmap(textView), x: 10)
                #expect(abs(CGFloat(try #require(rows.first)) - line.top) <= 1)
                #expect(abs(CGFloat(try #require(rows.last)) + 1 - line.bottom) <= 1)
                textView.setSelectedRange(NSRange(location: line.range.location + 1, length: 0))
                textView.updateInsertionPointStateAndRestartTimer(true)
                let caret = caretRows(try editorBitmap(textView))
                #expect(abs(CGFloat(try #require(caret.first)) - line.top) <= 1)
                #expect(abs(CGFloat(try #require(caret.last)) + 1 - line.bottom) <= 1)
            }
        }
    }

    @Test func caretRespectsAffinityAtLineBoundaries() throws {
        for leading: CGFloat in [10, 200, 0] {
            for content in ["HHHH HHHH HHHH", "HHHH\nHHHH"] {
                let (canvas, textView) = try textEditor(leading: leading, content: content)
                canvas.session.changeTextStyle {
                    $0.fontSize = 48
                    $0.boxSize = CGSize(width: 180, height: 700)
                }
                canvas.synchronizeDisplay()
                let window = TextEditingWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = try #require(canvas.inlineTextEditor)
                defer { window.orderOut(nil) }
                #expect(window.makeFirstResponder(textView))
                let layout = try #require(textView.layoutManager)
                layout.ensureLayout(for: try #require(textView.textContainer))
                let font = try #require(NSFont(name: "Helvetica", size: 48))
                var lines: [NSRange] = []
                layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { _, _, _, glyphs, _ in
                    lines.append(glyphs)
                }
                #expect(lines.count >= 2)
                for index in 1..<lines.count {
                    let boundary = layout.characterIndexForGlyph(at: lines[index].location)
                    for affinity: NSSelectionAffinity in [.upstream, .downstream] {
                        textView.setSelectedRange(NSRange(location: boundary, length: 0), affinity: affinity, stillSelecting: false)
                        textView.updateInsertionPointStateAndRestartTimer(true)
                        let rows = caretRows(try editorBitmap(textView))
                        // Only a soft wrap has two visual positions for the same insertion index.
                        let line = lines[affinity == .upstream && !content.contains("\n") ? index - 1 : index]
                        let baseline = textView.textContainerOrigin.y
                            + layout.lineFragmentRect(forGlyphAt: line.location, effectiveRange: nil).minY
                            + layout.location(forGlyphAt: line.location).y
                        #expect(abs(CGFloat(try #require(rows.first)) - (baseline - font.ascender)) <= 1,
                                "leading \(leading), affinity \(affinity), content \(content.debugDescription): caret top")
                        #expect(abs(CGFloat(try #require(rows.last)) + 1 - (baseline + abs(font.descender))) <= 1,
                                "leading \(leading), affinity \(affinity), content \(content.debugDescription): caret bottom")
                    }
                }
            }
        }
    }

    @Test func theCaretDisappearsWhenTheEditorLosesFocus() throws {
        let (canvas, textView) = try textEditor(leading: 10, content: "Hg")
        let window = TextEditingWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = try #require(canvas.inlineTextEditor)
        defer { window.orderOut(nil) }
        #expect(window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.updateInsertionPointStateAndRestartTimer(true)
        #expect(!caretRows(try editorBitmap(textView)).isEmpty)
        #expect(window.makeFirstResponder(nil))
        #expect(caretRows(try editorBitmap(textView)).isEmpty, "a font-height caret must be erased when focus leaves")
    }

    @Test func caretBlinkCallbacksRepaintTheFullHeight() throws {
        let (canvas, textView) = try textEditor(leading: 10, content: "Hg")
        let window = TextEditingWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = try #require(canvas.inlineTextEditor)
        defer { window.orderOut(nil) }
        #expect(window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.updateInsertionPointStateAndRestartTimer(true)
        let on = caretRows(try editorBitmap(textView))
        #expect(on.count == 200)
        let native = CGRect(x: 143.5, y: 190, width: 1, height: 10)
        // Deliver the timer's off/on requests outside a display pass, then render the requested redraw.
        textView.drawInsertionPoint(in: native, color: .black, turnedOn: false)
        let caret = try #require(textView.subviews.first { $0.identifier?.rawValue == "canvasTextCaret" })
        #expect(caret.isHidden)
        #expect(caret.frame.height == 200)
        #expect(caret.hitTest(CGPoint(x: caret.bounds.midX, y: caret.bounds.midY)) == nil)
        textView.drawInsertionPoint(in: native, color: .black, turnedOn: true)
        #expect(!caret.isHidden)
        #expect(caretRows(try editorBitmap(textView)) == on)
    }

    /// Leading shorter than the letters are tall closes the lines up over each other, but the first line has no line
    /// above to stand over: it stays whole, inside the box, rather than being cut off at the top of it.
    @Test func aShortLeadingKeepsTheFirstLineInTheBox() throws {
        let autoImage = try EditorSession.textImage(tallLetters(leading: 0, content: "H"))
        let auto = try #require(try inkRows(autoImage))
        let style = tallLetters(leading: 60, content: "H")
        #expect(EditorSession.firstLine(style).overflow > 0)
        let image = try EditorSession.textImage(style)
        let tight = try #require(try inkRows(image))
        #expect(tight.top >= Int(LayerTextStyle.padding) - 1, "the first line was cut off at the top of the box")
        #expect(abs((tight.bottom - tight.top) - (auto.bottom - auto.top)) <= 1)
    }

    @Test func linesAreTheLeadingApartWhenItIsShorterThanTheLetters() throws {
        // Each line's letter further right than the one above's, so lines that overlap can still be told apart.
        let image = try EditorSession.textImage(tallLetters(leading: 60, content: "H\n     H\n          H"))
        let columns = try inkedColumns(image)
        #expect(columns.count == 3)
        var baselines: [Int] = []
        for column in columns {
            let rows = try #require(try inkRows(image, columns: column))
            baselines.append(rows.bottom)
        }
        for (above, below) in zip(baselines, baselines.dropFirst()) {
            #expect(abs(below - above - 60) <= 1)
        }
        let whole = try #require(try inkRows(image))
        #expect(whole.top >= Int(LayerTextStyle.padding) - 1)
    }

    /// Leading as tall as the letters, Auto included, leaves text where it always was: the same size, and a click
    /// puts it in the same place.
    @Test(arguments: [0, 300] as [CGFloat])
    func leadingAsTallAsTheLettersChangesNothing(leading: CGFloat) throws {
        let style = tallLetters(leading: leading, content: "Two\nlines")
        let padding = LayerTextStyle.padding
        let descent = abs((EditorSession.textAttributes(style)[.font] as? NSFont)?.descender ?? 0)
        #expect(EditorSession.firstLine(style).overflow == 0)
        #expect(EditorSession.firstLine(style).baseline == padding + style.lineHeight - descent)
        let measured = EditorSession.attributedText(style).boundingRect(with: CGSize(width: 100_000, height: 100_000),
                                                                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        #expect(EditorSession.textBoxSize(style) == CGSize(width: max(16, ceil(measured.width + padding * 2 + style.fontSize * 0.1)),
                                                           height: max(16, ceil(max(measured.height, ceil(style.lineHeight)) + padding * 2))))
        let session = makeSession()
        session.textDefaults = style
        session.beginText(at: CGPoint(x: 300, y: 400))
        #expect(session.textDraft?.origin == CGPoint(x: 300 - padding, y: 400 - (padding + style.lineHeight - descent)))
    }

    /// A click puts the first baseline on the pointer however short the leading, the letters standing on it.
    @Test func aClickPutsTheFirstBaselineOnThePointerWithAShortLeading() throws {
        let session = makeSession()
        session.textDefaults = tallLetters(leading: 60, content: "")
        let click = CGPoint(x: 300, y: 400)
        session.beginText(at: click)
        session.textDraft?.style.content = "H"
        let draft = try #require(session.textDraft)
        #expect(abs(draft.origin.y + EditorSession.firstLine(draft.style).baseline - click.y) < 0.001)
        let image = try EditorSession.textImage(draft.style)
        let ink = try #require(try inkRows(image))
        #expect(abs(draft.origin.y + CGFloat(ink.bottom + 1) - click.y) <= 1)
    }

    /// Photoshop point text set tighter than its letters are tall still stands on its baseline, its first line whole.
    @Test func photoshopTextWithAShortLeadingKeepsItsBaselineAndFirstLine() throws {
        let parsed = try #require(PSDText.parse(extra: ["TySh": PSDFixture.tySh(text: "H", fontSize: 100, leading: 30, tx: 40, ty: 150)]))
        #expect(parsed.style.leading == 30)
        #expect(EditorSession.firstLine(parsed.style).overflow > 0)
        let rendered = try PSDText.render(parsed)
        let ink = try #require(try inkRows(rendered.image))
        #expect(ink.top >= Int(LayerTextStyle.padding) - 1)
        #expect(abs(rendered.transform.origin.y + CGFloat(ink.bottom + 1) - 150) <= 1)
    }

    /// The editor lays the text out where the canvas draws it, so its caret and highlight fall on the letters, and
    /// keeps room above the first line for them to reach up into.
    @Test func theEditorSetsAShortLeadingsFirstLineWhereTheCanvasDoes() throws {
        let session = makeSession()
        session.textDefaults = tallLetters(leading: 60, content: "")
        session.beginText(at: CGPoint(x: 300, y: 300))
        session.textDraft?.style.content = "H\nH"
        let view = CanvasView(session: session)
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        view.synchronizeDisplay()
        let textView = try #require(view.inlineTextEditor?.textView)
        let style = try #require(session.textDraft?.style)
        let padding = LayerTextStyle.padding, overflow = EditorSession.firstLine(style).overflow
        #expect(textView.frame.minY == padding)
        #expect(abs(textView.textContainerOrigin.y - overflow) < 0.001)
        let room = EditorSession.textBoxSize(style).height - padding * 2 - overflow
        #expect(abs((textView.textContainer?.size.height ?? 0) - room) < 0.001)
        #expect(textView.letterReach == overflow)
    }

    @Test func cancelingPickerRestoresSelectionColors() throws {
        let session = makeSession()
        session.beginText(at: CGPoint(x: 30, y: 40))
        session.textDraft?.style.content = "Two words"
        session.textDraft?.selection = NSRange(location: 0, length: 3)
        session.setPaletteColor(red, background: false)
        let colored = try #require(session.textDraft?.style)
        #expect(colored.colorRuns?.count == 1)
        session.openColorPicker(background: false)
        try #require(session.colorPicker).hsb.setRGB(PaletteColor(red: 0, green: 0, blue: 1))
        session.previewTextColor()
        #expect(session.textDraft?.style.color(at: 0).blue == 1)
        session.closeColorPicker(commit: false)
        #expect(session.textDraft?.style == colored)
    }

    private func verticalStyle(_ content: String = "가", font: String = "AppleSDGothicNeo-Regular",
                               leading: CGFloat = 0) throws -> LayerTextStyle {
        var style = tallLetters(leading: leading, content: content)
        style.fontName = font
        // Decode the new field so these tests exercise behavior even before the model supports it.
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as? [String: Any])
        json["orientation"] = "Vertical"
        return try JSONDecoder().decode(LayerTextStyle.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func inkBounds(_ image: CGImage, red: Bool? = nil) throws -> CGRect {
        let bytes = try #require(image.dataProvider?.data) as Data
        var left = image.width, top = image.height, right = -1, bottom = -1
        for y in 0..<image.height { for x in 0..<image.width {
            let offset = y * image.bytesPerRow + x * 4
            guard bytes[offset + 3] > 0 else { continue }
            if let red, red ? bytes[offset] <= bytes[offset + 2] : bytes[offset + 2] <= bytes[offset] { continue }
            left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
        } }
        try #require(right >= left && bottom >= top)
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    @Test func missingOrientationKeepsLegacyHorizontalJSON() throws {
        let style = LayerTextStyle()
        let data = try JSONEncoder().encode(style)
        let restored = try JSONDecoder().decode(LayerTextStyle.self, from: data)
        #expect(restored == style)
        #expect(restored.orientation == nil && !restored.isVertical)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["orientation"] == nil)
    }

    @Test func horizontalOrientationIsOmittedWhenEncoded() throws {
        var style = try verticalStyle()
        #expect(style.isVertical)
        style.orientation = .horizontal
        #expect(!style.isVertical)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as? [String: Any])
        #expect(json["orientation"] == nil)
    }

    @Test func verticalOrientationSurvivesSavingAndRejectsVersionEleven() async throws {
        let session = makeSession()
        session.beginText(at: .zero)
        session.textDraft?.style = try verticalStyle()
        #expect(session.finishText())
        let snapshot = try #require(session.projectSnapshot())
        #expect(snapshot.manifest.version == 12)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Vertical-\(UUID()).comp")
        defer { try? FileManager.default.removeItem(at: url) }
        try await ProjectStore.shared.save(snapshot, to: url)
        let reopened = makeSession()
        reopened.installProject(try await ProjectStore.shared.load(from: url), from: url)
        let style = try #require(reopened.activeLayer?.liveText?.style)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as? [String: Any])
        #expect(json["orientation"] as? String == "Vertical")
        var legacy = snapshot.manifest
        legacy.version = 11
        try JSONEncoder().encode(legacy).write(to: url.appendingPathComponent("manifest.json"))
        do {
            _ = try await ProjectStore.shared.load(from: url)
            Issue.record("Version 11 with orientation should be rejected")
        } catch ProjectError.invalid {}
    }

    @Test func verticalCJKStaysUprightAndLatinRotates() throws {
        for (text, name) in [("가", "AppleSDGothicNeo-Regular"), ("あ", "HiraginoSans-W3"), ("A", "Helvetica")] {
            var horizontal = tallLetters(leading: 0, content: text)
            horizontal.fontName = name
            let upright = try inkBounds(EditorSession.textImage(horizontal))
            let vertical = try inkBounds(EditorSession.textImage(verticalStyle(text, font: name)))
            #expect(abs(vertical.width - (text == "A" ? upright.height : upright.width)) <= 1, "\(name) width")
            #expect(abs(vertical.height - (text == "A" ? upright.width : upright.height)) <= 1, "\(name) height")
        }
    }

    @Test func verticalColumnsProgressFromRightToLeft() throws {
        var style = try verticalStyle("가\n나")
        style.red = 1
        style.colorRuns = [LayerTextColorRun(location: 2, length: 1, red: 0, green: 0, blue: 1)]
        let image = try EditorSession.textImage(style)
        // Color isolates the two ink columns even when one Hangul glyph has gaps within it.
        let first = try inkBounds(image, red: true), second = try inkBounds(image, red: false)
        #expect(first.minX > second.maxX)
        #expect(abs(first.minY - second.minY) <= 1)
    }

    @Test func verticalColumnSpacingFollowsLeading() throws {
        for leading: CGFloat in [60, 200, 0] {
            var style = try verticalStyle("가\n　　　가", leading: leading)
            style.boxSize = CGSize(width: 700, height: 1200)
            style.red = 1
            style.colorRuns = [LayerTextColorRun(location: 2, length: 4, red: 0, green: 0, blue: 1)]
            let image = try EditorSession.textImage(style)
            let first = try inkBounds(image, red: true), second = try inkBounds(image, red: false)
            #expect(abs(first.midX - second.midX - style.lineHeight) <= 1, "leading \(leading)")
        }
    }

    @Test func verticalFirstEmBoxMeetsRightPaddingWithAnyLeading() throws {
        for (text, name) in [("가", "AppleSDGothicNeo-Regular"), ("あ", "HiraginoSans-W3")] {
            for leading: CGFloat in [60, 200, 0] {
                var style = try verticalStyle(text, font: name, leading: leading)
                style.boxSize = CGSize(width: 700, height: 700)
                let font = try #require(NSFont(name: name, size: style.fontSize))
                var character = try #require(text.utf16.first), glyph: CGGlyph = 0
                #expect(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1))
                var translation = CGSize.zero
                CTFontGetVerticalTranslationsForGlyphs(font, &glyph, &translation, 1)
                let ink = try inkBounds(EditorSession.textImage(style))
                let expectedRight = 700 - LayerTextStyle.padding - style.fontSize / 2
                    + translation.width + font.boundingRect(forGlyph: NSGlyph(glyph)).maxX
                #expect(abs(ink.maxX - expectedRight) <= 1, "\(name), leading \(leading)")
                #expect(ink.maxX <= 700 - LayerTextStyle.padding + 1)
            }
        }
    }

    @Test func verticalAlignmentMovesAlongTheColumn() throws {
        for (text, name) in [("가", "AppleSDGothicNeo-Regular"), ("あ", "HiraginoSans-W3")] {
            var style = try verticalStyle(text, font: name)
            style.boxSize = CGSize(width: 700, height: 800)
            let font = try #require(NSFont(name: name, size: style.fontSize))
            var character = try #require(text.utf16.first), glyph: CGGlyph = 0
            #expect(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1))
            var advance = CGSize.zero, translation = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .vertical, &glyph, &advance, 1)
            CTFontGetVerticalTranslationsForGlyphs(font, &glyph, &translation, 1)
            let top = LayerTextStyle.padding - translation.height - font.boundingRect(forGlyph: NSGlyph(glyph)).maxY
            for (alignment, fraction): (Compositor.TextAlignment, CGFloat) in [(.left, 0), (.center, 0.5), (.right, 1)] {
                style.alignment = alignment
                let ink = try inkBounds(EditorSession.textImage(style))
                let expected = top + (800 - 2 * LayerTextStyle.padding - advance.width) * fraction
                #expect(abs(ink.minY - floor(expected)) <= 1, "\(name), \(alignment)")
                let vertical = EditorSession.verticalLayout(style, size: try #require(style.boxSize))
                let position = vertical.layoutManager.location(forGlyphAt: 0).x + vertical.drawingOrigin.x
                let emStart = LayerTextStyle.padding + (800 - 2 * LayerTextStyle.padding - advance.width) * fraction
                #expect(abs(position - emStart) <= 1, "the em advance, before raster rounding")
            }
        }
    }

    @Test func verticalPointSizeMeasuresColumnsAndEmptyText() throws {
        for leading: CGFloat in [60, 200, 0] {
            var style = try verticalStyle("あ\nああ", font: "HiraginoSans-W3", leading: leading)
            let size = EditorSession.textBoxSize(style)
            #expect(abs(size.width - (200 + style.lineHeight + 24)) <= 1)
            #expect(abs(size.height - 424) <= 1)
            style.content = ""
            #expect(abs(EditorSession.textBoxSize(style).width - 224) <= 1)
            style.content = "あ\n"
            #expect(abs(EditorSession.textBoxSize(style).width - (200 + style.lineHeight + 24)) <= 1)
        }
    }


    @Test func orientationButtonChangesDefaultsAndReturnsToHorizontal() throws {
        let session = makeSession()
        let controls = TypeControls(session: session)
        controls.toggleOrientation()
        #expect(session.textDefaults.isVertical)
        #expect(session.textDraft == nil)
        controls.toggleOrientation()
        #expect(session.textDefaults.orientation == nil)
    }

    @Test func orientationButtonEditsSelectedOrDraftTextWithOneUndo() throws {
        for editing in [false, true] {
            let session = makeSession()
            session.beginText(at: .zero)
            session.textDraft?.style.content = "가나"
            session.textDraft?.style.fontName = "AppleSDGothicNeo-Regular"
            #expect(session.finishText())
            let old = try #require(session.activeLayer?.liveText?.style)
            let undoCount = session.history.undoCount
            if editing { session.editActiveText() }
            TypeControls(session: session).toggleOrientation()
            #expect(session.textDraft?.style.isVertical == true)
            #expect(session.history.undoCount == undoCount)
            #expect(session.finishText())
            #expect(session.activeLayer?.liveText?.style.isVertical == true)
            #expect(session.history.undoCount == undoCount + 1)
            session.undo()
            #expect(session.activeLayer?.liveText?.style == old)
        }
    }

    @Test func verticalAlignmentButtonsUseTopCenterAndBottomLabels() {
        for (alignment, horizontal, vertical): (Compositor.TextAlignment, String, String) in [
            (.left, "Align left", "Align top"), (.center, "Align center", "Align center"), (.right, "Align right", "Align bottom")
        ] {
            #expect(TypeControls.alignmentLabel(alignment, vertical: false) == horizontal)
            #expect(TypeControls.alignmentLabel(alignment, vertical: true) == vertical)
        }
    }

    private func expectPoint(_ actual: CGPoint, _ expected: CGPoint, tolerance: CGFloat = 1) {
        #expect(abs(actual.x - expected.x) <= tolerance)
        #expect(abs(actual.y - expected.y) <= tolerance)
    }

    @Test func verticalPointClickAndGrowthKeepTheUpperRight() throws {
        for rotation: CGFloat in [0, 30] {
            let session = makeSession()
            session.textDefaults = try verticalStyle("", leading: 10)
            let click = CGPoint(x: 400, y: 180)
            session.beginText(at: click, newLayer: true)
            let canvas = CanvasView(session: session)
            canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
            session.textDraft?.style.content = "가"
            canvas.synchronizeDisplay()
            let first = try #require(canvas.inlineTextEditor?.shownTransform)
            expectPoint(CGPoint(x: first.origin.x + first.size.width - LayerTextStyle.padding - 100,
                                y: first.origin.y + LayerTextStyle.padding), click)
            session.textDraft?.style.content = "가\n나"
            canvas.synchronizeDisplay()
            let newGrowth = try #require(canvas.inlineTextEditor?.shownTransform)
            expectPoint(newGrowth.point(CGPoint(x: 1, y: 0)), first.point(CGPoint(x: 1, y: 0)))
            #expect(session.finishText())
            #expect(session.activeLayer?.transform == newGrowth)
            let index = try #require(session.document?.layers.firstIndex { $0.id == session.activeLayerID })
            session.document?.layers[index].transform.rotation = rotation
            session.editActiveText()
            canvas.synchronizeDisplay()
            let before = try #require(canvas.inlineTextEditor?.shownTransform)
            session.textDraft?.style.content += "\n다"
            canvas.synchronizeDisplay()
            let after = try #require(canvas.inlineTextEditor?.shownTransform)
            expectPoint(after.point(CGPoint(x: 1, y: 0)), before.point(CGPoint(x: 1, y: 0)))
            #expect(after.size.width > before.size.width)
            #expect(session.finishText())
            let committed = try #require(session.activeLayer?.transform)
            expectPoint(committed.point(CGPoint(x: 1, y: 0)), before.point(CGPoint(x: 1, y: 0)))
            #expect(committed == after)
        }
    }

    @Test func orientationSwitchPinsThePreviousCornerThenUsesTheNewDirection() throws {
        let session = makeSession()
        session.textDefaults = try verticalStyle("")
        session.textDefaults.orientation = nil
        session.beginText(at: CGPoint(x: 300, y: 300))
        session.textDraft?.style.content = "가나"
        #expect(session.finishText())
        let index = try #require(session.document?.layers.firstIndex { $0.id == session.activeLayerID })
        session.document?.layers[index].transform.rotation = 30
        session.editActiveText()
        let canvas = CanvasView(session: session)
        canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        canvas.synchronizeDisplay()
        let horizontal = try #require(canvas.inlineTextEditor?.shownTransform)
        session.changeTextStyle { $0.orientation = .vertical }
        canvas.synchronizeDisplay()
        let vertical = try #require(canvas.inlineTextEditor?.shownTransform)
        expectPoint(vertical.point(.zero), horizontal.point(.zero))
        session.textDraft?.style.content += "\n다"
        canvas.synchronizeDisplay()
        let grown = try #require(canvas.inlineTextEditor?.shownTransform)
        expectPoint(grown.point(CGPoint(x: 1, y: 0)), vertical.point(CGPoint(x: 1, y: 0)))
        session.changeTextStyle { $0.orientation = nil }
        canvas.synchronizeDisplay()
        let back = try #require(canvas.inlineTextEditor?.shownTransform)
        expectPoint(back.point(CGPoint(x: 1, y: 0)), grown.point(CGPoint(x: 1, y: 0)))
        session.textDraft?.style.content += "라마"
        canvas.synchronizeDisplay()
        let final = try #require(canvas.inlineTextEditor?.shownTransform)
        expectPoint(final.point(.zero), back.point(.zero))
        #expect(session.finishText())
        #expect(session.activeLayer?.transform == final)
    }

    @Test func verticalEditorCoordinatesMatchInkAndHitTestingThroughTransforms() throws {
        for (rotation, flipX, flipY) in [(0.0, false, false), (30.0, false, false),
                                       (30.0, true, false), (30.0, false, true)] {
            let session = makeSession()
            var style = try verticalStyle("가\n나", leading: 200)
            style.boxSize = CGSize(width: 480, height: 500)
            style.red = 1; style.green = 0; style.blue = 0
            style.colorRuns = [LayerTextColorRun(location: 2, length: 1, red: 0, green: 0, blue: 1)]
            session.textDefaults = style
            session.beginText(in: CGRect(origin: CGPoint(x: 100, y: 50), size: style.boxSize!))
            session.textDraft?.style = style
            #expect(session.finishText())
            let index = try #require(session.document?.layers.firstIndex { $0.id == session.activeLayerID })
            session.document?.layers[index].transform.rotation = rotation
            session.document?.layers[index].transform.flipX = flipX
            session.document?.layers[index].transform.flipY = flipY
            session.editActiveText()
            let canvas = CanvasView(session: session)
            canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
            session.viewport.resize(to: canvas.bounds.size, backingScale: 1, documentSize: nil)
            let window = TextEditingWindow(contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = canvas
            canvas.synchronizeDisplay()
            let editor = try #require(canvas.inlineTextEditor), view = editor.textView
            #expect(view.layoutOrientation == .vertical)
            let transform = try #require(editor.shownTransform)
            let image = try EditorSession.textImage(style)
            for (character, red) in [(0, true), (2, false)] {
                let ink = try #require(try inkBounds(image, red: red))
                let center = CGPoint(x: ink.midX / CGFloat(image.width), y: ink.midY / CGFloat(image.height))
                    .applying(transform.unitToDocument)
                let canvasPoint = session.viewport.viewPoint(from: center, documentSize: try #require(session.document?.size))
                let rect = view.firstRect(forCharacterRange: NSRange(location: character, length: 1), actualRange: nil)
                let onCanvas = canvas.convert(window.convertFromScreen(rect), from: nil)
                #expect(onCanvas.contains(canvasPoint), "firstRect must cover its rendered glyph")
                let insertion = view.characterIndexForInsertion(at: view.convert(canvasPoint, from: canvas))
                #expect(insertion == character || insertion == character + 1)
            }
            window.contentView = nil
        }
    }

    @Test func verticalSelectionAndCaretCoverEmInsteadOfLeading() throws {
        for leading: CGFloat in [10, 200, 0] {
            let session = makeSession()
            session.textDefaults = try verticalStyle("", leading: leading)
            session.beginText(at: CGPoint(x: 400, y: 200))
            session.textDraft?.style.content = "가\n나\n"
            let canvas = CanvasView(session: session)
            canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
            session.viewport.resize(to: canvas.bounds.size, backingScale: 1, documentSize: nil)
            let window = TextEditingWindow(contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = canvas
            canvas.synchronizeDisplay()
            let editor = try #require(canvas.inlineTextEditor), view = editor.textView
            let style = try #require(session.textDraft?.style)
            let layout = EditorSession.verticalLayout(style, size: EditorSession.textBoxSize(style))
            #expect(abs(view.textContainerOrigin.y - layout.columnOffset) <= 1)
            let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
            manager.ensureLayout(for: container)
            for character in [0, 2] {
                view.setSelectedRange(NSRange(location: character, length: 1))
                let rect = try #require(view.selectionRects.first)
                #expect(abs(rect.height - 200) <= 1)
                let projected = view.convert(rect, to: editor)
                #expect(abs(projected.width - 200) <= 1)
                #expect(abs(projected.maxX - (editor.bounds.width - LayerTextStyle.padding - CGFloat(character / 2) * style.lineHeight)) <= 1)
            }
            for character in [0, 2, 4] {
                view.setSelectedRange(NSRange(location: character, length: 0))
                window.makeFirstResponder(view)
                let fragment = character == 4 ? manager.extraLineFragmentRect
                    : manager.lineFragmentRect(forGlyphAt: character, effectiveRange: nil)
                view.drawInsertionPoint(in: CGRect(x: view.textContainerOrigin.x, y: fragment.minY + view.textContainerOrigin.y,
                                                   width: 1, height: style.lineHeight), color: .black, turnedOn: true)
                let caret = try #require(view.subviews.first { $0.identifier?.rawValue == "canvasTextCaret" })
                #expect(abs(caret.frame.height - 200) <= 1)
                let projected = view.convert(caret.frame, to: editor)
                #expect(abs(projected.maxX - (editor.bounds.width - LayerTextStyle.padding - CGFloat(character / 2) * style.lineHeight)) <= 1)
            }
            window.contentView = nil
        }
    }

    @Test func orientationRoundTripCommitsItsChangedAnchor() throws {
        let session = makeSession()
        session.textDefaults = try verticalStyle("")
        session.textDefaults.orientation = nil
        session.beginText(at: CGPoint(x: 300, y: 300))
        session.textDraft?.style.content = "가나"
        #expect(session.finishText())
        let before = try #require(session.activeLayer?.transform)
        session.editActiveText()
        let canvas = CanvasView(session: session)
        canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        canvas.synchronizeDisplay()
        session.changeTextStyle { $0.orientation = .vertical }
        canvas.synchronizeDisplay()
        session.changeTextStyle { $0.orientation = nil }
        canvas.synchronizeDisplay()
        let shown = try #require(canvas.inlineTextEditor?.shownTransform)
        #expect(shown != before)
        #expect(session.finishText())
        #expect(session.activeLayer?.transform == shown)
        session.undo()
        #expect(session.activeLayer?.transform == before)
    }

}
