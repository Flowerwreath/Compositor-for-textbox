import AppKit

nonisolated enum TextAlignment: String, Codable, CaseIterable, Sendable {
    case left = "Left", center = "Center", right = "Right"
}

nonisolated enum TextOrientation: String, Codable, CaseIterable, Sendable {
    case horizontal = "Horizontal", vertical = "Vertical"
}

nonisolated struct LayerTextStyle: Codable, Equatable, Sendable {
    var content = String(localized: "Text")
    var fontName = "Helvetica"
    var fontSize: CGFloat = 72
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alignment: TextAlignment = .left
    var orientation: TextOrientation? = nil {
        didSet { if orientation == .horizontal { orientation = nil } }
    }
    var isVertical: Bool { orientation == .vertical }
    var tracking: CGFloat = 0
    /// Baseline to baseline, in layer pixels, as Photoshop's Leading is. 0 is Auto: 120% of the font size.
    var leading: CGFloat = 0
    var autoLeading: CGFloat { fontSize * 1.2 }
    var lineHeight: CGFloat { leading > 0 ? leading : autoLeading }
    /// The gap between the text and its box, in layer pixels — the same for point text and a fixed box, so turning
    /// one into the other doesn't move the text, and wide enough to leave the box's edges easy to grab.
    static let padding: CGFloat = 12
    /// Fixed paragraph bounds in layer pixels. Nil supports older point-text layers.
    var boxSize: CGSize? = nil
    var boxIsValid: Bool {
        guard let boxSize else { return true }
        return boxSize.width.isFinite && boxSize.height.isFinite && (16...DocumentLimits.maxSideExtent).contains(boxSize.width)
            && (16...DocumentLimits.maxSideExtent).contains(boxSize.height) && boxSize.width * boxSize.height <= DocumentLimits.maxSurfaceExtent
    }
    /// Letters painted in a color other than `red`/`green`/`blue`, in UTF-16 offsets into `content`, sorted and not
    /// overlapping. Nil when the whole text is one color.
    var colorRuns: [LayerTextColorRun]? = nil
    /// Letters set in a face other than `fontName`, in the same offsets. Nil when the whole text is one face.
    var fontRuns: [LayerTextFontRun]? = nil
    var isValid: Bool {
        content.utf16.count <= 100_000 && boxIsValid
        && fontSize.isFinite && (1...2000).contains(fontSize)
        && [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
        && tracking.isFinite && (-100...1000).contains(tracking)
        && leading.isFinite && (0...5000).contains(leading)
        && colorRunsAreValid && fontRunsAreValid
    }
    private var colorRunsAreValid: Bool {
        guard let colorRuns else { return true }
        var end = 0
        for run in colorRuns {
            guard run.location >= end, run.length > 0, run.location <= Int.max - run.length,
                  [run.red, run.green, run.blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return false }
            end = run.location + run.length
        }
        return !colorRuns.isEmpty && end <= content.utf16.count
    }
    private var fontRunsAreValid: Bool {
        guard let fontRuns else { return true }
        var end = 0
        for run in fontRuns {
            guard run.location >= end, run.length > 0, run.location <= Int.max - run.length,
                  !run.fontName.isEmpty, run.fontName.count <= 200, !run.fontName.contains(where: \.isNewline) else { return false }
            end = run.location + run.length
        }
        return !fontRuns.isEmpty && end <= content.utf16.count
    }

    /// The color of the UTF-16 unit at `index`.
    func color(at index: Int) -> PaletteColor {
        let run = colorRuns?.first { $0.location <= index && index < $0.location + $0.length }
        return run.map { PaletteColor(red: $0.red, green: $0.green, blue: $0.blue) } ?? PaletteColor(red: red, green: green, blue: blue)
    }

    /// Paints `range` in `color`. An empty range, or one covering the whole text, recolors all of it.
    mutating func setColor(_ color: PaletteColor, in range: NSRange) {
        let count = content.utf16.count
        let start = max(0, min(range.location, count)), end = max(start, min(range.location + range.length, count))
        if start == end || (start == 0 && end == count) {
            red = color.red; green = color.green; blue = color.blue
            colorRuns = nil
            return
        }
        var colors = unitColors
        for index in start..<end { colors[index] = color }
        setUnitColors(colors)
    }

    /// The face of the UTF-16 unit at `index`.
    func fontName(at index: Int) -> String {
        fontRuns?.first { $0.location <= index && index < $0.location + $0.length }?.fontName ?? fontName
    }

    /// The one face covering `range`, or nil when that range is empty or uses more than one.
    func uniformFontName(in range: NSRange) -> String? {
        let count = content.utf16.count
        let start = max(0, min(range.location, count))
        let end = max(start, min(range.location + range.length, count))
        guard end > start else { return nil }
        let face = fontName(at: start)
        var index = start
        for run in fontRuns ?? [] where run.location < end && run.location + run.length > index {
            if run.location > index, fontName != face { return nil }
            if run.fontName != face { return nil }
            index = min(end, max(index, run.location + run.length))
        }
        if index < end, fontName != face { return nil }
        return face
    }

    /// Sets the face of `range`. An empty range, or one covering the whole text, changes all of it.
    mutating func setFont(_ name: String, in range: NSRange) {
        guard !name.isEmpty, name.count <= 200, !name.contains(where: \.isNewline) else { return }
        let count = content.utf16.count
        let start = max(0, min(range.location, count)), end = max(start, min(range.location + range.length, count))
        if start == end || (start == 0 && end == count) {
            fontName = name
            fontRuns = nil
            return
        }
        var fonts = unitFonts
        for index in start..<end { fonts[index] = name }
        setUnitFonts(fonts)
    }

    /// Keeps each letter's color and face when `range` of `content` is replaced by `length` new UTF-16 units, which
    /// take them from the letter before, as typing does. Call before `content` changes.
    mutating func replaceCharacters(in range: NSRange, withLength length: Int) {
        let count = content.utf16.count
        let start = max(0, min(range.location, count)), end = max(start, min(range.location + range.length, count))
        if colorRuns != nil {
            var colors = unitColors
            let inherited = start > 0 ? colors[start - 1] : (end > start ? colors[start] : colors.first ?? PaletteColor(red: red, green: green, blue: blue))
            colors.replaceSubrange(start..<end, with: repeatElement(inherited, count: max(0, length)))
            setUnitColors(colors)
        }
        if fontRuns != nil {
            var fonts = unitFonts
            let inherited = start > 0 ? fonts[start - 1] : (end > start ? fonts[start] : fonts.first ?? fontName)
            fonts.replaceSubrange(start..<end, with: repeatElement(inherited, count: max(0, length)))
            setUnitFonts(fonts)
        }
    }

    private var unitColors: [PaletteColor] {
        let base = PaletteColor(red: red, green: green, blue: blue)
        var colors = Array(repeating: base, count: content.utf16.count)
        for run in colorRuns ?? [] {
            let color = PaletteColor(red: run.red, green: run.green, blue: run.blue)
            for index in max(0, run.location)..<min(colors.count, run.location + run.length) { colors[index] = color }
        }
        return colors
    }

    private mutating func setUnitColors(_ colors: [PaletteColor]) {
        let base = PaletteColor(red: red, green: green, blue: blue)
        var runs: [LayerTextColorRun] = []
        for (index, color) in colors.enumerated() where color != base {
            if let last = runs.last, last.location + last.length == index,
               PaletteColor(red: last.red, green: last.green, blue: last.blue) == color {
                runs[runs.count - 1].length += 1
            } else {
                runs.append(LayerTextColorRun(location: index, length: 1, red: color.red, green: color.green, blue: color.blue))
            }
        }
        colorRuns = runs.isEmpty ? nil : runs
    }

    private var unitFonts: [String] {
        var fonts = Array(repeating: fontName, count: content.utf16.count)
        for run in fontRuns ?? [] {
            for index in max(0, run.location)..<min(fonts.count, run.location + run.length) { fonts[index] = run.fontName }
        }
        return fonts
    }

    private mutating func setUnitFonts(_ fonts: [String]) {
        if let first = fonts.first, fonts.allSatisfy({ $0 == first }) {
            fontName = first
            fontRuns = nil
            return
        }
        var runs: [LayerTextFontRun] = []
        for (index, name) in fonts.enumerated() where name != fontName {
            if let last = runs.last, last.location + last.length == index, last.fontName == name {
                runs[runs.count - 1].length += 1
            } else {
                runs.append(LayerTextFontRun(location: index, length: 1, fontName: name))
            }
        }
        fontRuns = runs.isEmpty ? nil : runs
    }
}

nonisolated struct LayerTextColorRun: Codable, Equatable, Sendable {
    var location: Int
    var length: Int
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
}

nonisolated struct LayerTextFontRun: Codable, Equatable, Sendable {
    var location: Int
    var length: Int
    var fontName: String
}

/// TextKit lays a vertical container out in rotated coordinates: x goes down, y goes left.
final class VerticalTextContainer: NSTextContainer {
    override var layoutOrientation: NSLayoutManager.TextLayoutOrientation { .vertical }
}

/// Keeps the storage alive with its layout, and exposes the same placement to the canvas and the editor.
struct VerticalTextLayout {
    let storage: NSTextStorage
    let layoutManager: NSLayoutManager
    let container: NSTextContainer
    /// Signed distance from right padding to the container origin. Negative removes spare leading before the em.
    let columnOffset: CGFloat
    /// The last em can end before or after its line fragment; preserve that room when fitting columns.
    let trailingInset: CGFloat
    let columnSpacing: CGFloat
    let firstColumnWidth: CGFloat
    var drawingOrigin: CGPoint { CGPoint(x: LayerTextStyle.padding, y: LayerTextStyle.padding + columnOffset) }
    var usedRect: CGRect {
        var rect = layoutManager.usedRect(for: container)
        if layoutManager.extraLineFragmentTextContainer === container {
            // TextKit gives a vertical trailing empty line an extra half-em; it is still only one column.
            rect.size.height = layoutManager.extraLineFragmentRect.minY + columnSpacing
        }
        return rect
    }
}

/// Inspect TextKit's actual drawing matrices: upright glyphs use a centered em, sideways glyphs a font baseline.
/// This also handles fallback fonts and mixed faces without a separate Unicode orientation table.
nonisolated class VerticalEmLayoutManager: NSLayoutManager {
    private var measuring = false
    private var emBounds = CGRect.null

    func measureEmBounds(for glyphs: NSRange) -> CGRect {
        emBounds = .null
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Suppress painting while TextKit supplies its actual fallback fonts and vertical matrices.
        if let context = try? BrushRaster.context(width: 1, height: 1, mask: false) {
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            measuring = true
            drawGlyphs(forGlyphRange: glyphs, at: .zero)
            measuring = false
        }
        return emBounds
    }

    override func showCGGlyphs(_ glyphs: UnsafePointer<CGGlyph>, positions: UnsafePointer<CGPoint>, count: Int,
                               font: NSFont, textMatrix: CGAffineTransform, attributes: [NSAttributedString.Key: Any],
                               in context: CGContext) {
        guard measuring else {
            super.showCGGlyphs(glyphs, positions: positions, count: count, font: font,
                               textMatrix: textMatrix, attributes: attributes, in: context)
            return
        }
        for index in 0..<count {
            let top: CGFloat, width: CGFloat
            if abs(textMatrix.b) > 0.5 {
                var glyph = glyphs[index], translation = CGSize.zero
                CTFontGetVerticalTranslationsForGlyphs(font, &glyph, &translation, 1)
                top = positions[index].y + translation.width - font.pointSize / 2
                width = font.pointSize
            } else {
                top = positions[index].y - font.ascender
                width = font.ascender + abs(font.descender)
            }
            emBounds = emBounds.union(CGRect(x: 0, y: top, width: 1, height: width))
        }
    }
}

/// The cached raster participates in the existing compositor. Pixel edits rasterize the layer;
/// transforms and masks keep the source text editable, just as shape layers keep their source.
nonisolated struct LayerText: Equatable, @unchecked Sendable {
    var style: LayerTextStyle
    let image: CGImage
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.style == rhs.style && lhs.image === rhs.image }
    static func loaded(_ style: LayerTextStyle?, image: CGImage?) -> LayerText? {
        guard let style, style.isValid, let image else { return nil }
        return LayerText(style: style, image: image)
    }
}

extension ImageLayer {
    var liveText: LayerText? {
        guard let text, let image = asset?.image, image === text.image else { return nil }
        return text
    }
}

struct TextDraft: Identifiable {
    let id = UUID()
    let documentID: UUID
    let layerID: UUID?
    var origin: CGPoint { didSet { if origin != oldValue { pointPlacement = nil } } }
    var transform: LayerTransform? = nil
    var style: LayerTextStyle
    /// What is selected in the on-canvas editor, in UTF-16 offsets into `style.content`. Color and font apply to it.
    var selection = NSRange(location: 0, length: 0)
    /// The last point-text placement, so a direction switch pins the old corner once, then grows in the new direction.
    var pointPlacement: TextPointPlacement? = nil

    mutating func place(_ transform: LayerTransform, size: CGSize) {
        if style.boxSize == nil {
            // Point text reads its pinned placement first and keeps the size and direction it grew from.
            var placement = pointPlacement ?? TextPointPlacement(
                transform: transform, size: size, vertical: style.isVertical)
            placement.transform = transform
            pointPlacement = placement
        } else {
            self.transform = transform
            origin = transform.origin
        }
    }

    mutating func textTransform(size: CGSize, layer: ImageLayer?) -> LayerTransform {
        guard style.boxSize == nil else {
            pointPlacement = nil
            var result = transform ?? layer?.transform ?? LayerTransform(origin: origin, size: size)
            if transform == nil, let asset = layer?.asset {
                let anchor = result.point(.zero)
                result.size = CGSize(width: size.width * result.size.width / CGFloat(asset.image.width),
                                     height: size.height * result.size.height / CGFloat(asset.image.height))
                let moved = result.point(.zero)
                result.origin.x += anchor.x - moved.x
                result.origin.y += anchor.y - moved.y
            }
            return result
        }
        let originalSize = layer?.asset.map { CGSize(width: $0.image.width, height: $0.image.height) } ?? size
        let previous = pointPlacement ?? TextPointPlacement(
            transform: transform ?? layer?.transform ?? LayerTransform(origin: origin, size: size),
            size: originalSize, vertical: layer?.liveText?.style.isVertical ?? style.isVertical)
        let corner = CGPoint(x: previous.vertical ? 1 : 0, y: 0)
        let anchor = previous.transform.point(corner)
        var result = previous.transform
        if size != previous.size {
            result.size = CGSize(width: size.width * result.size.width / max(1, previous.size.width),
                                 height: size.height * result.size.height / max(1, previous.size.height))
        }
        let moved = result.point(corner)
        result.origin.x += anchor.x - moved.x
        result.origin.y += anchor.y - moved.y
        pointPlacement = TextPointPlacement(transform: result, size: size, vertical: style.isVertical)
        return result
    }
}

struct TextPointPlacement: Equatable {
    var transform: LayerTransform
    var size: CGSize
    var vertical: Bool
}

extension EditorSession {
    func beginText(at point: CGPoint, newLayer: Bool = false) {
        guard canEditLayers, textDraft == nil, let document, point.x.isFinite, point.y.isFinite else { return }
        let visible = document.effectiveVisibleIDs
        let target = newLayer ? nil : document.layers.reversed().first {
            visible.contains($0.id) && $0.liveText != nil && $0.transform.contains(point)
        }
        if let target { selectLayer(target.id) }
        var style = target?.liveText?.style ?? textDefaults
        if target == nil {
            style.content = ""
            style.colorRuns = nil
            style.fontRuns = nil
            // New text starts in the foreground color, the same as every other tool that lays down color.
            if !isMaskSelected {
                style.red = foregroundColor.red; style.green = foregroundColor.green; style.blue = foregroundColor.blue
            }
            // A click makes point text: no box of its own, so what is typed decides how big the layer is. Dragging
            // a box out instead (beginText(in:)) sets boxSize, and so does resizing one by its handles.
            style.boxSize = nil
        }
        tool = .type
        // Horizontal clicks start the baseline; vertical clicks start the first column's centerline.
        let size = Self.textBoxSize(style)
        let origin: CGPoint
        if let target { origin = target.origin }
        else if style.isVertical {
            let layout = Self.verticalLayout(style, size: size)
            origin = CGPoint(x: point.x - size.width + LayerTextStyle.padding + layout.firstColumnWidth / 2,
                             y: point.y - LayerTextStyle.padding)
        } else {
            origin = CGPoint(x: point.x - LayerTextStyle.padding, y: point.y - Self.firstLine(style).baseline)
        }
        textDraft = TextDraft(documentID: document.id, layerID: target?.id, origin: origin, transform: target?.transform, style: style)
        if target == nil {
            textDraft?.pointPlacement = TextPointPlacement(transform: LayerTransform(origin: origin, size: size),
                                                         size: size, vertical: style.isVertical)
        }
    }

    func editActiveText() {
        guard canEditLayers, textDraft == nil, let document, let layer = activeLayer, let text = layer.liveText else { return }
        tool = .type
        textDraft = TextDraft(documentID: document.id, layerID: layer.id, origin: layer.origin, transform: layer.transform, style: text.style)
    }

    @discardableResult
    func applyText(_ draft: TextDraft) -> Bool {
        guard document?.id == draft.documentID, draft.style.isValid else { return false }
        let pending = textDraft
        textDraft = nil
        guard canEditLayers else { textDraft = pending; return false }
        var succeeded = false
        defer { if !succeeded { textDraft = pending } }
        if draft.layerID == nil, draft.style.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            succeeded = true
            return true
        }
        do {
            let image = try Self.textImage(draft.style)
            let text = LayerText(style: draft.style, image: image)
            if let id = draft.layerID {
                guard let index = document?.layers.firstIndex(where: { $0.id == id }),
                      let layer = document?.layers[index], layer.liveText != nil, let asset = layer.asset else { return false }
                var placed = draft
                let transform = placed.textTransform(size: CGSize(width: image.width, height: image.height), layer: layer)
                if layer.liveText?.style == draft.style && transform == layer.transform { succeeded = true; return true }
                let thumbnail = try PixelInvert.thumbnail(of: image)
                guard transform.isValid else { throw ProjectError.tooLarge }
                beginEdit("Edit Text")
                if layer.mask?.placement == nil { document?.layers[index].mask?.placement = layer.maskTransform }
                document?.layers[index].asset = ImportedImage(image: image, thumbnail: thumbnail, name: asset.name)
                document?.layers[index].text = text
                document?.layers[index].transform = transform
                endEdit()
            } else {
                var placed = draft
                let transform = placed.textTransform(size: CGSize(width: image.width, height: image.height), layer: nil)
                addPixelLayer(image, at: transform.origin, name: Self.layerName(for: draft.style.content), editName: "New Text Layer",
                              dropsSelection: false, text: text, transform: transform)
            }
            succeeded = true
            textDefaults = draft.style
            textDefaults.colorRuns = nil
            textDefaults.fontRuns = nil
            textDraft = nil
            canvasFocusRequest += 1
            return true
        } catch {
            brushError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func finishText() -> Bool {
        guard let draft = textDraft else { return true }
        return applyText(draft)
    }

    func cancelText() { textDraft = nil; canvasFocusRequest += 1 }

    func beginText(in rect: CGRect) {
        guard canEditLayers, textDraft == nil, rect.width.isFinite, rect.height.isFinite else { return }
        var style = textDefaults
        style.boxSize = CGSize(width: max(16, rect.width.rounded()), height: max(16, rect.height.rounded()))
        guard style.boxIsValid else { brushError = "That text box exceeds the \(DocumentLimits.maxSide.formatted())-pixel or \(DocumentLimits.maxSurfaceMegapixels)-megapixel limit."; return }
        beginText(at: rect.origin, newLayer: true)
        // A dragged box is exactly where it was drawn.
        textDraft?.origin = rect.origin
        textDraft?.style.boxSize = style.boxSize
    }

    /// Paints a text layer's letters in `color`, keeping it editable text. Used by Fill with Foreground/Background;
    /// false when the layer isn't live text or its pixels couldn't be redrawn, so the caller fills as usual.
    @discardableResult
    func recolorText(_ id: UUID, to color: PaletteColor) -> Bool {
        guard canEditLayers, let index = document?.layers.firstIndex(where: { $0.id == id }),
              let layer = document?.layers[index], let text = layer.liveText, let asset = layer.asset else { return false }
        var style = text.style
        guard style.red != color.red || style.green != color.green || style.blue != color.blue || style.colorRuns != nil else { return true }
        style.setColor(color, in: NSRange(location: 0, length: 0))
        guard style.isValid, let image = try? Self.textImage(style), let thumbnail = try? PixelInvert.thumbnail(of: image) else { return false }
        finishOpacityEdit()
        beginEdit("Fill Text")
        document?.layers[index].asset = ImportedImage(image: image, thumbnail: thumbnail, name: asset.name)
        document?.layers[index].text = LayerText(style: style, image: image)
        endEdit()
        return true
    }

    var currentTextStyle: LayerTextStyle { textDraft?.style ?? activeLayer?.liveText?.style ?? textDefaults }

    var textPlacement: LayerTransform? {
        guard var draft = textDraft else { return nil }
        return refreshTextPlacement(&draft).transform
    }

    private func refreshTextPlacement(_ draft: inout TextDraft) -> (transform: LayerTransform, size: CGSize) {
        let size = Self.textBoxSize(draft.style)
        let layer = document?.layers.first { $0.id == draft.layerID }
        return (draft.textTransform(size: size, layer: layer), size)
    }

    var textRotation: CGFloat? {
        if textDraft != nil { return textPlacement?.rotation }
        guard let layer = activeLayer, layer.liveText != nil else { return nil }
        return layer.transform.rotation
    }

    func setTextRotation(_ degrees: CGFloat) {
        if textDraft == nil, activeLayer?.liveText != nil { editActiveText() }
        guard var draft = textDraft else { return }
        let placement = refreshTextPlacement(&draft)
        var transform = placement.transform
        transform.rotation = degrees
        guard transform.isValid else { return }
        draft.place(transform, size: placement.size)
        textDraft = draft
    }

    /// Keep the flip in the draft so committing or discarding text also commits or discards its placement.
    func flipText(horizontally: Bool) {
        guard var draft = textDraft else { return }
        let placement = refreshTextPlacement(&draft)
        let center = placement.transform.center
        let transform = placement.transform.mirrored(horizontally: horizontally,
                                                     across: horizontally ? center.x : center.y)
        draft.place(transform, size: placement.size)
        textDraft = draft
    }

    /// While the font menu is open, the text being edited shows the face under the pointer; `endFontPreview` puts it
    /// back. Only text already being edited: a selected text layer isn't opened for a preview.
    func previewFont(_ name: String) {
        guard var draft = textDraft else { return }
        let original = fontPreviewOriginal ?? draft.style
        fontPreviewOriginal = original
        var style = original
        style.setFont(name, in: draft.selection)
        guard style.isValid, style != draft.style else { return }
        draft.style = style
        textDraft = draft
    }
    /// The previewed face was chosen: keep the text as it shows, rather than putting it back and applying it again.
    func keepFontPreview() { fontPreviewOriginal = nil }
    func endFontPreview() {
        guard let original = fontPreviewOriginal else { return }
        fontPreviewOriginal = nil
        if var draft = textDraft, draft.style != original { draft.style = original; textDraft = draft }
    }

    func changeTextStyle(_ change: (inout LayerTextStyle) -> Void) {
        if textDraft == nil, activeLayer?.liveText != nil { editActiveText() }
        if var draft = textDraft {
            change(&draft.style)
            guard draft.style.isValid else { return }
            textDraft = draft
        } else {
            var style = textDefaults
            change(&style)
            if style.isValid { textDefaults = style }
        }
    }

    /// A text layer's name: its first words on one line. Line breaks and runs of spaces become single spaces, so a
    /// paragraph never makes the row in the Layers panel taller than one line.
    static func layerName(for content: String) -> String {
        let flattened = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return flattened.isEmpty ? String(localized: "Text") : String(flattened.prefix(40))
    }

    nonisolated static func textAttributes(_ style: LayerTextStyle) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = style.alignment == .left ? .left : style.alignment == .center ? .center : .right
        let font = NSFont(name: style.fontName, size: style.fontSize) ?? NSFont.systemFont(ofSize: style.fontSize)
        // Leading is the line's whole height, so the lines close up (and eventually overlap) as it comes down,
        // exactly as Photoshop's does. Auto is 120% of the size.
        _ = font
        paragraph.minimumLineHeight = style.lineHeight
        paragraph.maximumLineHeight = style.lineHeight
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: NSFont(name: style.fontName, size: style.fontSize) ?? NSFont.systemFont(ofSize: style.fontSize),
                .foregroundColor: NSColor(srgbRed: style.red, green: style.green, blue: style.blue, alpha: 1),
                .paragraphStyle: paragraph, .kern: style.tracking]
    }

    /// The tallest ascent and the deepest descent among the faces `range` of the text is set in (the text's own face
    /// where it has no letters), and how far those letters stand out of the top of their line. A fixed line height
    /// keeps its baseline the descent up from the bottom of the line, so leading shorter than the letters are tall
    /// leaves their tops above it, over the line before. Leading as tall as the letters, Auto included, leaves none.
    nonisolated static func letterMetrics(_ style: LayerTextStyle, in range: NSRange) -> (ascent: CGFloat, descent: CGFloat, overflow: CGFloat) {
        let count = style.content.utf16.count
        let start = max(0, min(range.location, count)), end = max(start, min(range.location + range.length, count))
        var faces: Set<String> = []
        var covered = start
        for run in style.fontRuns ?? [] where run.location < end && run.location + run.length > start {
            if run.location > covered { faces.insert(style.fontName) }
            faces.insert(run.fontName)
            covered = max(covered, run.location + run.length)
        }
        if covered < end || start == end { faces.insert(style.fontName) }
        var ascent: CGFloat = 0, descent: CGFloat = 0
        for face in faces {
            let font = NSFont(name: face, size: style.fontSize) ?? NSFont.systemFont(ofSize: style.fontSize)
            ascent = max(ascent, font.ascender)
            descent = max(descent, abs(font.descender))
        }
        return (ascent, descent, max(0, ascent + descent - style.lineHeight))
    }

    /// Where the first line sits in the text's box. There is no line above for its letters to stand over, so the text
    /// is set `overflow` lower, below the padding, to keep them in the box; `baseline` is then the first baseline's
    /// height from the top of the box. Leading as tall as the letters leaves the text where it always was.
    nonisolated static func firstLine(_ style: LayerTextStyle) -> (overflow: CGFloat, baseline: CGFloat) {
        let letters = letterMetrics(style, in: (style.content as NSString).paragraphRange(for: NSRange(location: 0, length: 0)))
        return (letters.overflow, LayerTextStyle.padding + letters.overflow + style.lineHeight - letters.descent)
    }

    /// Build once in rotated coordinates, then move the first column's em edge to the right padding.
    static func verticalLayout(_ style: LayerTextStyle, size: CGSize) -> VerticalTextLayout {
        let padding = LayerTextStyle.padding
        let storage = NSTextStorage(attributedString: attributedText(style))
        let layout = VerticalEmLayoutManager()
        let container = VerticalTextContainer(size: CGSize(width: max(1, size.height - 2 * padding), height: 100_000))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        // An empty column still has the typing face's em. Remove the measuring space before returning the layout.
        let empty = storage.length == 0
        if empty { storage.setAttributedString(NSAttributedString(string: " ", attributes: textAttributes(style))) }
        layout.ensureLayout(for: container)
        var first = NSRange(location: 0, length: 0)
        if layout.numberOfGlyphs > 0 {
            _ = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: &first)
        }
        let measured = layout.measureEmBounds(for: first)
        let bounds = measured.isNull
            ? CGRect(x: 0, y: style.lineHeight - style.fontSize, width: 1, height: style.fontSize) : measured
        let offset = -bounds.minY, trailing = bounds.maxY - style.lineHeight
        if empty { storage.setAttributedString(attributedText(style)) }
        container.size.height = max(1, size.width - 2 * padding - offset - trailing)
        layout.ensureLayout(for: container)
        return VerticalTextLayout(storage: storage, layoutManager: layout, container: container,
                                  columnOffset: offset, trailingInset: trailing, columnSpacing: style.lineHeight,
                                  firstColumnWidth: bounds.height)
    }

    /// How big point text is: what it measures, plus its padding and whatever its first line's letters need above
    /// it. A caret's worth of width so an empty line still has somewhere to type.
    static func textBoxSize(_ style: LayerTextStyle) -> CGSize {
        if let boxSize = style.boxSize { return boxSize }
        if style.isVertical {
            var measuredStyle = style
            measuredStyle.alignment = .left
            let vertical = verticalLayout(measuredStyle, size: CGSize(width: 100_000, height: 100_000))
            let used = vertical.usedRect
            return CGSize(width: max(16, ceil(max(style.lineHeight, used.height) + vertical.columnOffset
                                              + vertical.trailingInset + LayerTextStyle.padding * 2)),
                          height: max(16, ceil(max(used.width, style.fontSize * 0.1) + LayerTextStyle.padding * 2)))
        }
        let string = attributedText(style)
        let padding = LayerTextStyle.padding
        let measured = string.boundingRect(with: CGSize(width: 100_000, height: 100_000),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading])
        let line = ceil(style.lineHeight)
        return CGSize(width: max(16, ceil(measured.width + padding * 2 + style.fontSize * 0.1)),
                      height: max(16, ceil(max(measured.height, line) + firstLine(style).overflow + padding * 2)))
    }

    /// The text as it is drawn and measured, with each letter's own face and color.
    static func attributedText(_ style: LayerTextStyle) -> NSMutableAttributedString {
        let string = NSMutableAttributedString(string: style.content, attributes: textAttributes(style))
        for run in style.fontRuns ?? [] where Self.containsTextRun(run.location, run.length, in: string.length) {
            let font = NSFont(name: run.fontName, size: style.fontSize) ?? NSFont.systemFont(ofSize: style.fontSize)
            string.addAttribute(.font, value: font, range: NSRange(location: run.location, length: run.length))
        }
        for run in style.colorRuns ?? [] where Self.containsTextRun(run.location, run.length, in: string.length) {
            string.addAttribute(.foregroundColor, value: NSColor(srgbRed: run.red, green: run.green, blue: run.blue, alpha: 1),
                                range: NSRange(location: run.location, length: run.length))
        }
        return string
    }

    static func containsTextRun(_ location: Int, _ length: Int, in total: Int) -> Bool {
        length > 0 && location >= 0 && location <= total - length
    }

    static func textImage(_ style: LayerTextStyle) throws -> CGImage {
        guard style.isValid else { throw ProjectError.invalid }
        let string = attributedText(style)
        let padding = LayerTextStyle.padding
        let size = textBoxSize(style)
        let width = ceil(size.width), height = ceil(size.height)
        guard width.isFinite, height.isFinite, width >= 1, height >= 1,
              width <= DocumentLimits.maxSideExtent, height <= DocumentLimits.maxSideExtent, width * height <= DocumentLimits.maxSurfaceExtent else { throw ProjectError.tooLarge }
        let context = try BrushRaster.context(width: Int(width), height: Int(height), mask: false)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        if style.isVertical {
            let vertical = verticalLayout(style, size: CGSize(width: width, height: height))
            context.translateBy(x: width, y: 0)
            context.rotate(by: .pi / 2)
            vertical.layoutManager.drawGlyphs(forGlyphRange: vertical.layoutManager.glyphRange(for: vertical.container),
                                              at: vertical.drawingOrigin)
            guard let image = context.makeImage() else { throw ExportError.render }
            return image
        }
        // A short leading's first line is set lower, keeping its letters in the box; a fixed box has that much less
        // room for lines.
        let overflow = firstLine(style).overflow
        let storage = NSTextStorage(attributedString: string)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(1, width - 2 * padding), height: max(1, height - 2 * padding - overflow)))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let glyphs = layout.glyphRange(for: container)
        layout.drawGlyphs(forGlyphRange: glyphs, at: CGPoint(x: padding, y: padding + overflow))
        guard let image = context.makeImage() else { throw ExportError.render }
        return image
    }
}
