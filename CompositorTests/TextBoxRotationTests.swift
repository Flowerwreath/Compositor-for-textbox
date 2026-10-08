import AppKit
import Testing
@testable import Compositor

@MainActor
struct TextBoxRotationTests {
    private final class TextEditingWindow: NSWindow {
        // The test host runs in the background. Give AppKit a key-window condition without stealing user focus.
        override var isKeyWindow: Bool { true }
    }

    /// An open text box on an 800x600 canvas that is the content view of a window, so event locations are defined.
    @MainActor private struct Rig {
        let session: EditorSession
        let canvas: CanvasView
        let window: NSWindow
        let editor: InlineTextEditor
        var shown: LayerTransform { editor.shownTransform! }
        var scale: CGFloat { session.viewport.pointsPerPixel }

        /// A point in the box's own unit coordinates (outside 0...1 is fine) as a location in the window.
        func windowPoint(_ unit: CGPoint, of transform: LayerTransform? = nil) -> CGPoint {
            let pixel = (transform ?? shown).point(unit)
            return canvas.convert(session.viewport.viewPoint(from: pixel, documentSize: session.document!.size), to: nil)
        }
        /// A point the given number of screen points past the top-right corner on both of the box's own axes.
        func zone(past points: CGFloat = 14, of transform: LayerTransform? = nil) -> CGPoint {
            let box = transform ?? shown
            return windowPoint(CGPoint(x: 1 + points / (box.size.width * scale), y: -points / (box.size.height * scale)), of: box)
        }
        /// The window location of a document point.
        func windowPoint(forPixel pixel: CGPoint) -> CGPoint {
            canvas.convert(session.viewport.viewPoint(from: pixel, documentSize: session.document!.size), to: nil)
        }
        func event(_ type: NSEvent.EventType, at location: CGPoint, shift: Bool = false) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: shift ? .shift : [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        /// Drags from `start` to `end` through the editor, the way the mouse does.
        func drag(from start: CGPoint, to end: CGPoint, shift: Bool = false) {
            editor.mouseDown(with: event(.leftMouseDown, at: start))
            editor.mouseDragged(with: event(.leftMouseDragged, at: end, shift: shift))
            editor.mouseUp(with: event(.leftMouseUp, at: end))
        }
        /// `point` (document pixels) turned about the box's center by `degrees`, clockwise on screen.
        func turned(_ pixel: CGPoint, by degrees: CGFloat, about center: CGPoint) -> CGPoint {
            let angle = degrees * .pi / 180
            let dx = pixel.x - center.x, dy = pixel.y - center.y
            return CGPoint(x: center.x + dx * cos(angle) - dy * sin(angle), y: center.y + dx * sin(angle) + dy * cos(angle))
        }
    }

    private func makeRig(box: Bool = true, vertical: Bool = false, content: String = "Hello") throws -> Rig {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600, emptyLayer: true)
        session.selectTool(.type)
        var style = session.textDefaults
        style.orientation = vertical ? .vertical : .horizontal
        session.textDefaults = style
        if box {
            session.beginText(in: CGRect(x: 200, y: 150, width: 300, height: 160))
        } else {
            session.beginText(at: CGPoint(x: 200, y: 150))
        }
        session.textDraft?.style.content = content
        return try attach(session)
    }

    private func attach(_ session: EditorSession) throws -> Rig {
        let canvas = CanvasView(session: session)
        canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        session.viewport.resize(to: canvas.bounds.size, backingScale: 1, documentSize: nil)
        let window = TextEditingWindow(contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.synchronizeDisplay()
        return Rig(session: session, canvas: canvas, window: window, editor: try #require(canvas.inlineTextEditor))
    }

    @Test func settingBoxTextRotationKeepsItsCenterAndSize() throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600, emptyLayer: true)
        session.beginText(in: CGRect(x: 200, y: 150, width: 300, height: 160))
        let before = try #require(session.textPlacement)
        let size = try #require(session.textDraft?.style.boxSize)

        session.setTextRotation(30)

        let after = try #require(session.textPlacement)
        #expect(after.rotation == 30)
        #expect(abs(after.center.x - before.center.x) < 0.5 && abs(after.center.y - before.center.y) < 0.5)
        #expect(session.textDraft?.style.boxSize == size)
    }

    @Test func settingPointTextRotationCommitsItsAngle() throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600, emptyLayer: true)
        session.beginText(at: CGPoint(x: 200, y: 150))
        let initialSize = try #require(session.textDraft?.pointPlacement?.size)
        session.textDraft?.style.content = "Hi"
        let style = try #require(session.textDraft?.style)
        let size = EditorSession.textBoxSize(style)
        #expect(size != initialSize)
        let before = try #require(session.textPlacement)

        for degrees: CGFloat in [30, 60, 30] {
            session.setTextRotation(degrees)
            let placement = try #require(session.textPlacement)
            #expect(placement.rotation == degrees)
            #expect(abs(placement.size.width - size.width) < 0.5)
            #expect(abs(placement.size.height - size.height) < 0.5)
            #expect(abs(placement.center.x - before.center.x) < 0.5)
            #expect(abs(placement.center.y - before.center.y) < 0.5)
        }

        let draft = try #require(session.textDraft)
        #expect(draft.style.boxSize == nil)
        #expect(session.textPlacement?.rotation == 30)
        #expect(session.applyText(draft))
        let layer = try #require(session.activeLayer)
        #expect(layer.liveText != nil)
        #expect(layer.transform.rotation == 30)
        #expect(abs(layer.transform.center.x - before.center.x) < 0.5)
        #expect(abs(layer.transform.center.y - before.center.y) < 0.5)
    }

    @Test func settingSelectedTextRotationOpensItsDraft() throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600, emptyLayer: true)
        session.beginText(in: CGRect(x: 200, y: 150, width: 300, height: 160))
        session.textDraft?.style.content = "Hello"
        #expect(session.applyText(try #require(session.textDraft)))
        let layer = try #require(session.activeLayer)
        #expect(layer.liveText != nil)
        #expect(session.textDraft == nil)
        #expect(session.textRotation == layer.transform.rotation)

        session.setTextRotation(45)

        let draft = try #require(session.textDraft)
        #expect(draft.layerID == layer.id)
        #expect(session.textRotation == 45)
    }

    @Test func settingRotationWithoutTextDoesNotStartADraft() {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600, emptyLayer: true)
        #expect(session.activeLayer != nil)
        #expect(session.activeLayer?.liveText == nil)
        #expect(session.textRotation == nil)

        session.setTextRotation(45)

        #expect(session.textDraft == nil)
        #expect(session.textRotation == nil)
    }

    @Test func placingPointTextKeepsItsPreviousSizeAndDirection() throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600, emptyLayer: true)
        session.beginText(at: CGPoint(x: 200, y: 150))
        var draft = try #require(session.textDraft)
        draft.style.orientation = .horizontal
        let previousSize = CGSize(width: 80, height: 120)
        var transform = LayerTransform(origin: draft.origin, size: previousSize)
        draft.pointPlacement = TextPointPlacement(transform: transform, size: previousSize, vertical: true)
        transform.rotation = 30

        draft.place(transform, size: CGSize(width: 200, height: 50))

        let placement = try #require(draft.pointPlacement)
        #expect(placement.transform == transform)
        #expect(placement.size == previousSize)
        #expect(placement.vertical)
        #expect(draft.style.boxSize == nil)
    }

    @Test func boxTextRotatesAroundItsCenter() throws {
        let rig = try makeRig()
        defer { rig.window.contentView = nil }
        let before = rig.shown
        let size = try #require(rig.session.textDraft?.style.boxSize)
        let start = rig.zone()
        let startPixel = rig.shown.point(CGPoint(x: 1 + 14 / (before.size.width * rig.scale), y: -14 / (before.size.height * rig.scale)))
        let end = rig.windowPoint(forPixel: rig.turned(startPixel, by: 90, about: before.center))
        rig.drag(from: start, to: end)
        let after = try #require(rig.session.textDraft?.transform)
        #expect(after.rotation == 90)
        #expect(abs(after.center.x - before.center.x) < 0.5 && abs(after.center.y - before.center.y) < 0.5)
        #expect(rig.session.textDraft?.style.boxSize == size)
        #expect(rig.session.textDraft?.origin == after.origin)
    }

    @Test func shiftSnapsToFifteenDegreeSteps() throws {
        let rig = try makeRig()
        defer { rig.window.contentView = nil }
        let before = rig.shown
        let unit = CGPoint(x: 1 + 14 / (before.size.width * rig.scale), y: -14 / (before.size.height * rig.scale))
        let startPixel = before.point(unit)
        let end = rig.windowPoint(forPixel: rig.turned(startPixel, by: 37, about: before.center))
        rig.drag(from: rig.zone(), to: end, shift: true)
        #expect(rig.session.textDraft?.transform?.rotation == 30)
        let free = try makeRig()
        defer { free.window.contentView = nil }
        let freeStart = free.shown.point(unit)
        let freeEnd = free.windowPoint(forPixel: free.turned(freeStart, by: 37, about: free.shown.center))
        free.drag(from: free.zone(), to: freeEnd)
        let rotation = try #require(free.session.textDraft?.transform?.rotation)
        #expect(rotation == rotation.rounded())
        #expect(abs(rotation - 37) <= 1)
    }

    @Test func pointTextStaysPointTextAndGrowsFromItsRotatedCorner() throws {
        let rig = try makeRig(box: false, content: "Hi")
        defer { rig.window.contentView = nil }
        let layersBefore = try #require(rig.session.document?.layers.count)
        let before = rig.shown
        let unit = CGPoint(x: 1 + 14 / (before.size.width * rig.scale), y: -14 / (before.size.height * rig.scale))
        let end = rig.windowPoint(forPixel: rig.turned(before.point(unit), by: 90, about: before.center))
        rig.drag(from: rig.zone(), to: end)
        #expect(rig.session.textDraft?.style.boxSize == nil)
        #expect(rig.shown.rotation == 90)
        let corner = rig.shown.point(.zero)
        rig.session.textDraft?.style.content = "Hi there"
        rig.canvas.synchronizeDisplay()
        #expect(rig.shown.rotation == 90)
        let moved = rig.shown.point(.zero)
        #expect(abs(moved.x - corner.x) < 1 && abs(moved.y - corner.y) < 1)
        let draft = try #require(rig.session.textDraft)
        #expect(rig.session.applyText(draft))
        let layer = try #require(rig.session.activeLayer)
        #expect(layer.transform.rotation == 90)
        let placed = layer.transform.point(.zero)
        #expect(abs(placed.x - corner.x) < 1 && abs(placed.y - corner.y) < 1)
        #expect(rig.session.document?.layers.count == layersBefore + 1)
        rig.session.undo()
        #expect(rig.session.document?.layers.count == layersBefore)
    }

    @Test func verticalPointTextRotatesAndKeepsItsTopRightCorner() throws {
        let rig = try makeRig(box: false, vertical: true, content: "가나")
        defer { rig.window.contentView = nil }
        let before = rig.shown
        let unit = CGPoint(x: 1 + 14 / (before.size.width * rig.scale), y: -14 / (before.size.height * rig.scale))
        let end = rig.windowPoint(forPixel: rig.turned(before.point(unit), by: 90, about: before.center))
        rig.drag(from: rig.zone(), to: end)
        #expect(rig.session.textDraft?.style.boxSize == nil)
        #expect(rig.shown.rotation == 90)
        let corner = rig.shown.point(CGPoint(x: 1, y: 0))
        rig.session.textDraft?.style.content = "가나다라"
        rig.canvas.synchronizeDisplay()
        #expect(rig.shown.rotation == 90)
        let moved = rig.shown.point(CGPoint(x: 1, y: 0))
        #expect(abs(moved.x - corner.x) < 1 && abs(moved.y - corner.y) < 1)
    }

    @Test func hitZonesAroundTheCorner() throws {
        let rig = try makeRig()
        defer { rig.window.contentView = nil }
        func hit(at window: CGPoint) -> NSView? {
            let inCanvas = rig.canvas.convert(window, from: nil)
            return rig.canvas.hitTest(rig.canvas.convert(inCanvas, to: rig.canvas.superview))
        }
        #expect(hit(at: rig.zone()) === rig.editor)
        #expect(hit(at: rig.zone(past: 60)) !== rig.editor)
        let corner = rig.windowPoint(CGPoint(x: 1, y: 0))
        #expect(hit(at: corner) === rig.editor)
        let size = try #require(rig.session.textDraft?.style.boxSize)
        rig.drag(from: corner, to: CGPoint(x: corner.x + 40, y: corner.y - 40))
        let after = try #require(rig.session.textDraft)
        #expect(try #require(after.style.boxSize).width > size.width)
        #expect(after.transform?.rotation == 0)
    }

    @Test func cursorTurnsIntoTheRotationCursorOnlyAtTheCorners() throws {
        let rig = try makeRig()
        defer { rig.window.contentView = nil; NSCursor.arrow.set() }
        NSCursor.arrow.set()
        rig.editor.pointerMoved(rig.event(.mouseMoved, at: rig.zone()))
        #expect(NSCursor.current === CanvasView.rotationCursor)
        NSCursor.arrow.set()
        // Over the middle of the top edge: a resize band, not the rotation zone.
        rig.editor.pointerMoved(rig.event(.mouseMoved, at: rig.windowPoint(CGPoint(x: 0.5, y: 0))))
        #expect(NSCursor.current !== CanvasView.rotationCursor)
        // Beside the middle of the right edge, just outside the band.
        NSCursor.arrow.set()
        let side = rig.windowPoint(CGPoint(x: 1 + 14 / (rig.shown.size.width * rig.scale), y: 0.5))
        rig.editor.pointerMoved(rig.event(.mouseMoved, at: side))
        #expect(NSCursor.current !== CanvasView.rotationCursor)
        // Farther out, nothing changes.
        NSCursor.arrow.set()
        rig.editor.pointerMoved(rig.event(.mouseMoved, at: rig.zone(past: 60)))
        #expect(NSCursor.current !== CanvasView.rotationCursor)
    }

    @Test func aRotatedLayerRotatesFromItsRotatedCorner() throws {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600, emptyLayer: true)
        session.selectTool(.type)
        session.beginText(in: CGRect(x: 200, y: 150, width: 300, height: 160))
        session.textDraft?.style.content = "Hello"
        let draft = try #require(session.textDraft)
        #expect(session.applyText(draft))
        let index = try #require(session.document?.layers.firstIndex { $0.id == session.activeLayerID })
        session.document?.layers[index].transform.rotation = 30
        session.editActiveText()
        let rig = try attach(session)
        defer { rig.window.contentView = nil; NSCursor.arrow.set() }
        let before = rig.shown
        #expect(before.rotation == 30)
        let start = rig.zone()
        func hit(at window: CGPoint) -> NSView? {
            rig.canvas.hitTest(rig.canvas.convert(rig.canvas.convert(window, from: nil), to: rig.canvas.superview))
        }
        #expect(hit(at: start) === rig.editor)
        rig.editor.pointerMoved(rig.event(.mouseMoved, at: start))
        #expect(NSCursor.current === CanvasView.rotationCursor)
        let unit = CGPoint(x: 1 + 14 / (before.size.width * rig.scale), y: -14 / (before.size.height * rig.scale))
        let end = rig.windowPoint(forPixel: rig.turned(before.point(unit), by: 45, about: before.center))
        rig.drag(from: start, to: end)
        #expect(rig.session.textDraft?.transform?.rotation == 75)
    }
}
