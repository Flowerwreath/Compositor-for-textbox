import AppKit

/// A corner-shaped double arrow keeps the direction of a text box's rotation zone visible as the box turns.
@MainActor
enum TextRotationCursor {
    private static var cursors: [Int: NSCursor] = [:]

    /// Whole-degree cursors are shared so pointer moves do not keep making images for the same angle.
    static func cursor(degrees: CGFloat) -> NSCursor {
        let angle = Int(normalized(degrees.rounded()))
        if let cursor = cursors[angle] { return cursor }
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            // In this unflipped image, the bend is at the top-right, with arrows pointing left and down.
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 6, y: 17))
            path.line(to: CGPoint(x: 17, y: 17))
            path.line(to: CGPoint(x: 17, y: 6))
            path.move(to: CGPoint(x: 9, y: 20))
            path.line(to: CGPoint(x: 6, y: 17))
            path.line(to: CGPoint(x: 9, y: 14))
            path.move(to: CGPoint(x: 14, y: 9))
            path.line(to: CGPoint(x: 17, y: 6))
            path.line(to: CGPoint(x: 20, y: 9))
            path.transform(using: AffineTransform(translationByX: -12, byY: -12))
            var rotation = AffineTransform()
            rotation.rotate(byDegrees: -CGFloat(angle))
            path.transform(using: rotation)
            path.transform(using: AffineTransform(translationByX: 12, byY: 12))
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.white.setStroke()
            path.lineWidth = 4
            path.stroke()
            NSColor.black.setStroke()
            path.lineWidth = 2
            path.stroke()
            return true
        }
        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
        cursors[angle] = cursor
        return cursor
    }

    /// The bend points away from the chosen unit corner, then follows the box's clockwise screen rotation.
    static func degrees(corner: CGPoint, boxRotation: CGFloat) -> CGFloat {
        let angle: CGFloat = corner.x == 1 ? (corner.y == 0 ? 0 : 90) : (corner.y == 1 ? 180 : 270)
        return normalized(angle + boxRotation)
    }

    private static func normalized(_ degrees: CGFloat) -> CGFloat {
        let angle = degrees.truncatingRemainder(dividingBy: 360)
        return angle < 0 ? angle + 360 : angle
    }
}
