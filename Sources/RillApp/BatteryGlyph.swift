import AppKit
import CoreImage

/// Menu bar battery in the style of macOS's own: a soft outline, a solid fill
/// to the exact charge level, and Apple's `bolt.fill` or
/// `powerplug.portrait.fill` knocked out of the fill. SF Symbols alone only
/// offer five levels and a bolt at 100 %, which looked small and coarse
/// (Felix, 2026-11-04). Template image, so it follows the menu bar tint.
enum BatteryGlyph {
    enum Mark { case none, bolt, plug }

    static let size = NSSize(width: 29, height: 14)
    private static let body = NSRect(x: 0.5, y: 0.5, width: 25.5, height: 13)

    /// Cache key: the image only changes with these.
    static func key(percent: Int, mark: Mark) -> String { "\(percent)-\(mark)" }

    static func image(percent: Int, mark: Mark) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current else { return false }

            let outline = NSBezierPath(roundedRect: body, xRadius: 4.2, yRadius: 4.2)
            outline.lineWidth = 1
            NSColor.black.withAlphaComponent(0.4).setStroke()
            outline.stroke()
            NSColor.black.withAlphaComponent(0.4).setFill()
            NSBezierPath(roundedRect: NSRect(x: body.maxX + 1.2, y: body.midY - 2.5, width: 1.8, height: 5),
                         xRadius: 0.9, yRadius: 0.9).fill()

            let inner = body.insetBy(dx: 2, dy: 2)
            let level = CGFloat(max(0, min(100, percent))) / 100
            if level > 0 {
                let bar = NSRect(x: inner.minX, y: inner.minY, width: max(1.5, inner.width * level), height: inner.height)
                let r = min(2.4, bar.width / 2)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: bar, xRadius: r, yRadius: r).fill()
            }

            guard let glyph = symbol(mark) else { return true }
            let r = NSRect(x: (inner.midX - glyph.size.width / 2).rounded(), y: inner.midY - glyph.size.height / 2,
                           width: glyph.size.width, height: glyph.size.height)
            // Knock out the mark grown evenly by 1.3 pt, inside the battery
            // only, so there is a clean gap around it and the outline stays whole.
            if let halo = dilated(glyph, by: 1.3) {
                ctx.saveGraphicsState()
                NSBezierPath(roundedRect: body.insetBy(dx: 1, dy: 1), xRadius: 3.4, yRadius: 3.4).addClip()
                halo.image.draw(in: r.insetBy(dx: -halo.pad, dy: -halo.pad), from: .zero, operation: .destinationOut, fraction: 1)
                ctx.restoreGraphicsState()
            }
            glyph.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "\(percent)%"
        return image
    }

    private static func symbol(_ mark: Mark) -> NSImage? {
        let name: String
        let point: CGFloat
        switch mark {
        case .none: return nil
        case .bolt: name = "bolt.fill"; point = 9
        case .plug: name = "powerplug.portrait.fill"; point = 8.5
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: point, weight: .semibold))
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// The glyph's shape grown outward by `points`, rendered at 8x, plus the
    /// padding (in points) added on each side.
    private static func dilated(_ glyph: NSImage, by points: CGFloat) -> (image: NSImage, pad: CGFloat)? {
        let scale: CGFloat = 8
        let pad = ceil(points) + 1
        let w = Int((glyph.size.width + pad * 2) * scale), h = Int((glyph.size.height + pad * 2) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ctx.scaleBy(x: scale, y: scale)
        glyph.draw(in: NSRect(x: pad, y: pad, width: glyph.size.width, height: glyph.size.height))
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { return nil }
        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIMorphologyMaximum") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(points * scale, forKey: kCIInputRadiusKey)
        guard let out = filter.outputImage?.cropped(to: input.extent),
              let result = ciContext.createCGImage(out, from: input.extent) else { return nil }
        return (NSImage(cgImage: result, size: NSSize(width: CGFloat(w) / scale, height: CGFloat(h) / scale)), pad)
    }
}
