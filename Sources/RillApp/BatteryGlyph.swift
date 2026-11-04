import AppKit

/// Menu bar battery: an outline filled to the charge level, with a bolt while
/// charging or a plug while plugged in and holding. Template image, so it
/// follows the menu bar's light or dark tint.
enum BatteryGlyph {
    enum Mark { case none, bolt, plug }

    static func image(percent: Int, mark: Mark) -> NSImage {
        let size = NSSize(width: 27, height: 13)
        let image = NSImage(size: size, flipped: false) { _ in
            let body = NSRect(x: 0.5, y: 0.5, width: 23, height: 12)
            let outline = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)
            outline.lineWidth = 1
            NSColor.black.withAlphaComponent(0.45).setStroke()
            outline.stroke()

            let nub = NSBezierPath(roundedRect: NSRect(x: 24.5, y: 4.5, width: 1.8, height: 4), xRadius: 0.9, yRadius: 0.9)
            NSColor.black.withAlphaComponent(0.45).setFill()
            nub.fill()

            let inner = body.insetBy(dx: 1.5, dy: 1.5)
            let level = CGFloat(max(0, min(100, percent))) / 100
            if level > 0 {
                let fill = NSRect(x: inner.minX, y: inner.minY, width: max(1.5, inner.width * level), height: inner.height)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: fill, xRadius: 2, yRadius: 2).fill()
            }

            guard let path = markPath(mark, center: NSPoint(x: body.midX, y: body.midY)),
                  let ctx = NSGraphicsContext.current else { return true }
            // Cut a halo around the mark, only inside the battery, so it reads
            // on top of the fill without breaking the outline.
            ctx.saveGraphicsState()
            NSBezierPath(rect: inner).addClip()
            ctx.compositingOperation = .destinationOut
            path.lineWidth = 2.4
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            path.fill()
            ctx.restoreGraphicsState()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func markPath(_ mark: Mark, center c: NSPoint) -> NSBezierPath? {
        switch mark {
        case .none:
            return nil
        case .bolt:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: c.x + 1.3, y: c.y + 4.4))
            p.line(to: NSPoint(x: c.x - 2.8, y: c.y - 0.5))
            p.line(to: NSPoint(x: c.x - 0.1, y: c.y - 0.5))
            p.line(to: NSPoint(x: c.x - 1.3, y: c.y - 4.4))
            p.line(to: NSPoint(x: c.x + 2.8, y: c.y + 0.7))
            p.line(to: NSPoint(x: c.x + 0.1, y: c.y + 0.7))
            p.close()
            return p
        case .plug:
            let p = NSBezierPath(roundedRect: NSRect(x: c.x - 2.2, y: c.y - 2.4, width: 4.4, height: 4.8), xRadius: 1.2, yRadius: 1.2)
            p.append(NSBezierPath(rect: NSRect(x: c.x + 2.2, y: c.y + 0.7, width: 2.2, height: 1.0)))
            p.append(NSBezierPath(rect: NSRect(x: c.x + 2.2, y: c.y - 1.7, width: 2.2, height: 1.0)))
            p.append(NSBezierPath(rect: NSRect(x: c.x - 5.2, y: c.y - 0.55, width: 3.0, height: 1.1)))
            return p
        }
    }
}
