import AppKit
import SwiftUI
import Testing
@testable import Compositor

@MainActor
struct TypeToolTests {
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
        #expect(snapshot.manifest.version == 11)
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
}
