import AppKit

/// Claude-style starburst drawn as an image, so it can turn smoothly instead
/// of cycling through text glyphs.
enum Spark {
    /// Uneven ray lengths give it the hand-drawn look of the Claude mark.
    private static let rays: [CGFloat] = [1, 0.74, 0.92, 0.68, 0.97, 0.79, 0.88, 0.7, 1, 0.76, 0.93, 0.71]

    /// `phase` in radians rotates the spark; `scale` shrinks it inside its box.
    static func image(size: CGFloat, color: NSColor, phase: CGFloat = 0, scale: CGFloat = 1) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect, color: color, phase: phase, scale: scale)
            return true
        }
    }

    static func draw(in rect: NSRect, color: NSColor, phase: CGFloat = 0, scale: CGFloat = 1) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * scale
        let path = NSBezierPath()
        path.lineWidth = radius * 0.15
        path.lineCapStyle = .round
        for (i, length) in rays.enumerated() {
            let angle = phase + CGFloat(i) / CGFloat(rays.count) * 2 * .pi
            let dx = cos(angle), dy = sin(angle)
            let inner = radius * 0.16
            let outer = (radius - path.lineWidth / 2) * length
            path.move(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
            path.line(to: CGPoint(x: center.x + dx * outer, y: center.y + dy * outer))
        }
        color.setStroke()
        path.stroke()
    }

    /// The app icon: white spark on a Claude-orange rounded square.
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset = rect.insetBy(dx: size * 0.1, dy: size * 0.1)
            Palette.claude.setFill()
            NSBezierPath(roundedRect: inset, xRadius: inset.width * 0.225, yRadius: inset.width * 0.225).fill()
            draw(in: inset.insetBy(dx: inset.width * 0.2, dy: inset.width * 0.2), color: .white, phase: 0.13)
            return true
        }
    }
}
