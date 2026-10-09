import AppKit
import Testing
@testable import Compositor

@MainActor
struct TextFlipTests {
    private final class TextEditingWindow: NSWindow {
        // The test host runs in the background, without taking focus from the user.
        override var isKeyWindow: Bool { true }
    }

    @MainActor private struct Rig {
        let session: EditorSession
        let canvas: CanvasView
        let window: NSWindow

        func event(at pixel: CGPoint) -> NSEvent {
            let point = session.viewport.viewPoint(from: pixel, documentSize: session.document!.size)
            return NSEvent.mouseEvent(with: .rightMouseDown, location: canvas.convert(point, to: nil),
                                     modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                     context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
    }

    private func makeSession(box: Bool = true) -> EditorSession {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600, emptyLayer: true)
        if box {
            session.beginText(in: CGRect(x: 200, y: 150, width: 300, height: 160))
        } else {
            session.beginText(at: CGPoint(x: 200, y: 150))
        }
        session.textDraft?.style.content = "Hello"
        return session
    }

    private func attach(_ session: EditorSession) -> Rig {
        let canvas = CanvasView(session: session)
        canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        session.viewport.resize(to: canvas.bounds.size, backingScale: 1, documentSize: nil)
        let window = TextEditingWindow(contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.synchronizeDisplay()
        return Rig(session: session, canvas: canvas, window: window)
    }

    private func invoke(_ title: String, in menu: NSMenu) throws {
        let item = try #require(menu.items.first { $0.title == title })
        let action = try #require(item.action)
        #expect(NSApplication.shared.sendAction(action, to: item.target, from: item))
    }

    private func expectNoFlipItems(_ menu: NSMenu?) {
        #expect(menu?.items.contains { $0.title == "Flip Horizontal" || $0.title == "Flip Vertical" } != true)
    }

    @Test func rotatedBoxFlipsAboutItsCenterWithoutResizing() throws {
        let session = makeSession()
        session.setTextRotation(30)
        let before = try #require(session.textPlacement)
        let size = try #require(session.textDraft?.style.boxSize)
        let undoCount = session.history.undoCount

        session.flipText(horizontally: true)

        let horizontal = try #require(session.textPlacement)
        #expect(horizontal.flipX != before.flipX)
        #expect(horizontal.flipY == before.flipY)
        #expect(horizontal.rotation == -30)
        #expect(abs(horizontal.center.x - before.center.x) < 0.5)
        #expect(abs(horizontal.center.y - before.center.y) < 0.5)
        #expect(session.textDraft?.style.boxSize == size)

        session.flipText(horizontally: false)

        let vertical = try #require(session.textPlacement)
        #expect(vertical.flipX == horizontal.flipX && vertical.flipY != horizontal.flipY)
        #expect(vertical.rotation == 30)
        #expect(abs(vertical.center.x - before.center.x) < 0.5)
        #expect(abs(vertical.center.y - before.center.y) < 0.5)
        #expect(session.textDraft?.style.boxSize == size)
        #expect(session.history.undoCount == undoCount)
    }

    @Test func pointTextRefreshesItsSizeBeforeFlippingAndCommitsAsPointText() throws {
        let session = makeSession(box: false)
        let initialSize = try #require(session.textDraft?.pointPlacement?.size)
        let before = try #require(session.textPlacement)
        #expect(before.size != initialSize)
        let undoCount = session.history.undoCount

        session.flipText(horizontally: true)

        let draft = try #require(session.textDraft)
        let after = try #require(session.textPlacement)
        #expect(draft.style.boxSize == nil)
        #expect(draft.pointPlacement?.size == before.size)
        #expect(after.flipX)
        #expect(after.size == before.size)
        #expect(abs(after.center.x - before.center.x) < 0.5)
        #expect(abs(after.center.y - before.center.y) < 0.5)
        #expect(session.history.undoCount == undoCount)
        #expect(session.applyText(draft))
        let layer = try #require(session.activeLayer)
        #expect(layer.liveText != nil && layer.liveText?.style.boxSize == nil)
        #expect(layer.transform.flipX)
        #expect(abs(layer.transform.center.x - before.center.x) < 0.5)
        #expect(abs(layer.transform.center.y - before.center.y) < 0.5)
        #expect(session.history.undoCount == undoCount + 1)
        #expect(session.history.undoName == "New Text Layer")
        session.undo()
        #expect(session.document?.layers.contains { $0.id == layer.id } == false)
    }

    @Test func editingMenuKeepsCopyAndAppendsWorkingFlipItems() throws {
        let rig = attach(makeSession())
        defer { rig.window.contentView = nil }
        let editor = try #require(rig.canvas.inlineTextEditor)
        let placement = try #require(rig.session.textPlacement)
        let menu = try #require(editor.textView.menu(for: rig.event(at: placement.center)))
        #expect(menu.items.contains { $0.action == #selector(NSText.copy(_:)) })
        #expect(Array(menu.items.suffix(2).map(\.title)) == ["Flip Horizontal", "Flip Vertical"])
        #expect(menu.items.dropLast(2).last?.isSeparatorItem == true)

        try invoke("Flip Horizontal", in: menu)

        #expect(rig.session.textPlacement?.flipX == true)
    }

    @Test func canvasMenuFlipsLiveTextWithOneUndoStep() throws {
        let session = makeSession()
        #expect(session.applyText(try #require(session.textDraft)))
        let before = try #require(session.activeLayer)
        session.selectTool(.move)
        let rig = attach(session)
        defer { rig.window.contentView = nil }
        let menu = try #require(rig.canvas.menu(for: rig.event(at: before.transform.center)))
        #expect(menu.items.map(\.title) == ["Flip Horizontal", "Flip Vertical"])
        let undoCount = session.history.undoCount

        try invoke("Flip Vertical", in: menu)

        #expect(session.activeLayer?.transform.flipY == true)
        #expect(session.activeLayer?.liveText != nil)
        #expect(session.history.undoCount == undoCount + 1)
        #expect(session.history.undoName == "Flip Vertical")
        session.undo()
        #expect(session.activeLayer?.transform == before.transform)
        #expect(session.activeLayer?.liveText != nil)
    }

    @Test func canvasMenuSelectsOnlyTheClickedTextLayerBeforeFlipping() throws {
        let session = makeSession()
        let pixel = try #require(session.document?.layers.first)
        #expect(session.applyText(try #require(session.textDraft)))
        let text = try #require(session.activeLayer)
        session.selectTool(.move)
        session.selectLayers([text.id, pixel.id], primary: pixel.id)
        let rig = attach(session)
        defer { rig.window.contentView = nil }
        let menu = try #require(rig.canvas.menu(for: rig.event(at: text.transform.center)))

        try invoke("Flip Horizontal", in: menu)

        #expect(session.selectedLayerIDs == [text.id])
        #expect(session.activeLayerID == text.id)
        #expect(session.activeLayer?.transform.flipX == true)
        #expect(session.document?.layers.first { $0.id == pixel.id }?.transform == pixel.transform)
        #expect(session.history.undoName == "Flip Horizontal")
    }

    @Test func canvasMenuExcludesBrushFamilyPixelLayersAndEmptyCanvas() throws {
        let session = makeSession()
        #expect(session.applyText(try #require(session.textDraft)))
        let text = try #require(session.activeLayer)
        let rig = attach(session)
        defer { rig.window.contentView = nil }
        for tool in NavigationTool.allCases where tool.isBrushTool {
            session.selectTool(tool)
            expectNoFlipItems(rig.canvas.menu(for: rig.event(at: text.transform.center)))
        }
        session.selectTool(.move)
        expectNoFlipItems(rig.canvas.menu(for: rig.event(at: CGPoint(x: 50, y: 50))))
        expectNoFlipItems(rig.canvas.menu(for: rig.event(at: CGPoint(x: 900, y: 700))))
    }

    @Test func canvasMenuExcludesFlipsWithAPendingCrop() throws {
        let session = makeSession()
        #expect(session.applyText(try #require(session.textDraft)))
        let text = try #require(session.activeLayer)
        session.selectTool(.crop)
        let crop = try #require(session.cropRect)
        #expect(session.tool == .crop)
        #expect(!session.canEditLayers)
        let rig = attach(session)
        defer { rig.window.contentView = nil }

        expectNoFlipItems(rig.canvas.menu(for: rig.event(at: text.transform.center)))

        #expect(session.cropRect == crop)
        #expect(session.activeLayer?.transform == text.transform)
    }

    @Test func canvasMenuExcludesFlipsWithAPendingTransform() throws {
        let session = makeSession()
        #expect(session.applyText(try #require(session.textDraft)))
        let text = try #require(session.activeLayer)
        session.selectTool(.move)
        session.beginTransform()
        let edit = try #require(session.transformEdit)
        #expect(session.tool == .move)
        #expect(edit.layerID == text.id)
        #expect(!session.canEditLayers)
        let rig = attach(session)
        defer { rig.window.contentView = nil }

        expectNoFlipItems(rig.canvas.menu(for: rig.event(at: text.transform.center)))

        #expect(session.transformEdit?.layerID == edit.layerID)
        #expect(session.transformEdit?.draft == edit.draft)
        #expect(session.activeLayer?.transform == text.transform)
    }

    @Test func canvasMenuOffersFlipsWithEveryNonBrushToolExceptCrop() throws {
        let session = makeSession()
        #expect(session.applyText(try #require(session.textDraft)))
        let text = try #require(session.activeLayer)
        let rig = attach(session)
        defer { rig.window.contentView = nil }
        for tool in NavigationTool.allCases where !tool.isBrushTool && tool != .crop {
            session.selectTool(tool)
            let menu = try #require(rig.canvas.menu(for: rig.event(at: text.transform.center)))
            #expect(menu.items.map(\.title) == ["Flip Horizontal", "Flip Vertical"])
        }
    }

    @Test func canvasMenuDoesNotOfferFlipsOutsideTheEditorWhileEditing() throws {
        let session = makeSession()
        #expect(session.applyText(try #require(session.textDraft)))
        let text = try #require(session.activeLayer)
        session.beginText(in: CGRect(x: 550, y: 350, width: 150, height: 100))
        let rig = attach(session)
        defer { rig.window.contentView = nil }
        expectNoFlipItems(rig.canvas.menu(for: rig.event(at: text.transform.center)))
    }

    @Test func flipWithoutADraftDoesNotEditTheSelectedTextLayer() throws {
        let session = makeSession()
        #expect(session.applyText(try #require(session.textDraft)))
        let before = try #require(session.activeLayer?.transform)
        let undoCount = session.history.undoCount
        session.flipText(horizontally: true)
        #expect(session.textDraft == nil)
        #expect(session.activeLayer?.transform == before)
        #expect(session.history.undoCount == undoCount)
    }

    @Test func existingTextFlipCommitsWithTheRestOfTheEdit() throws {
        let session = makeSession()
        #expect(session.applyText(try #require(session.textDraft)))
        let before = try #require(session.activeLayer)
        let undoCount = session.history.undoCount
        session.editActiveText()
        session.textDraft?.style.content = "Edited"
        session.flipText(horizontally: true)
        #expect(session.history.undoCount == undoCount)
        #expect(session.applyText(try #require(session.textDraft)))
        #expect(session.activeLayer?.transform.flipX == true)
        #expect(session.activeLayer?.liveText?.style.content == "Edited")
        #expect(session.history.undoCount == undoCount + 1)
        #expect(session.history.undoName == "Edit Text")
        session.undo()
        #expect(session.activeLayer?.transform == before.transform)
        #expect(session.activeLayer?.liveText?.style == before.liveText?.style)
    }

    @Test func escapeDiscardsTheDraftFlip() throws {
        let session = makeSession()
        #expect(session.applyText(try #require(session.textDraft)))
        let before = try #require(session.activeLayer?.transform)
        let undoCount = session.history.undoCount
        session.editActiveText()
        let rig = attach(session)
        defer { rig.window.contentView = nil }
        let editor = try #require(rig.canvas.inlineTextEditor)
        session.flipText(horizontally: true)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: rig.window.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        editor.textView.keyDown(with: escape)
        #expect(session.textDraft == nil)
        #expect(session.activeLayer?.transform == before)
        #expect(session.history.undoCount == undoCount)
    }
}
