import AppKit
import QuartzCore
import RillCore
import SwiftUI

/// The flow's ribbons as Core Animation layers. The light sweeping along each
/// ribbon and the shape easing between readings both run in the render
/// server, so the app does no per-frame work. Redrawing them from SwiftUI's
/// TimelineView cost 10–17 % of a core while the panel was open (2026-11-05).
struct RibbonLayerView: NSViewRepresentable {
    struct Ribbon: Equatable {
        var path: CGPath
        var x0: CGFloat, x1: CGFloat
        var top: CGFloat, bottom: CGFloat
        var from: NSColor, to: NSColor
        var watts: Double
        /// Where the watt label sits, and whether the ribbon is thick enough for it.
        var labelCenter: CGPoint
        var showsLabel: Bool

        static func == (a: Ribbon, b: Ribbon) -> Bool {
            a.path == b.path && a.x0 == b.x0 && a.x1 == b.x1 && a.from == b.from && a.to == b.to && a.watts == b.watts
                && a.labelCenter == b.labelCenter && a.showsLabel == b.showsLabel
        }
    }

    var ribbons: [Ribbon]
    var reduceMotion: Bool

    func makeNSView(context: Context) -> RibbonNSView { RibbonNSView() }

    func updateNSView(_ view: RibbonNSView, context: Context) {
        view.update(ribbons, reduceMotion: reduceMotion)
    }
}

final class RibbonNSView: NSView {
    private final class Layers {
        let fill = CAGradientLayer()
        let fillMask = CAShapeLayer()
        let sweepHost = CALayer()
        let sweepMask = CAShapeLayer()
        let sweeps = [CAGradientLayer(), CAGradientLayer()]
        let label = CATextLayer()
        var duration: CFTimeInterval = 0
        var span: (CGFloat, CGFloat) = (0, 0)
    }

    private var items: [Layers] = []
    private var current: [RibbonLayerView.Ribbon] = []
    /// Short enough that the SwiftUI tiles, which switch at once, never look
    /// detached from the ribbons for long.
    static let easeDuration: CFTimeInterval = 0.5

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func update(_ ribbons: [RibbonLayerView.Ribbon], reduceMotion: Bool) {
        guard let root = layer else { return }
        // A different number of ribbons is a different state; rebuild.
        if items.count != ribbons.count {
            items.forEach { $0.fill.removeFromSuperlayer(); $0.sweepHost.removeFromSuperlayer(); $0.label.removeFromSuperlayer() }
            items = ribbons.map { _ in makeLayers(in: root) }
        }
        current = ribbons
        let animate = !reduceMotion && window != nil
        applyFrames()
        for (r, l) in zip(ribbons, items) {

            // Morph the ribbon from where it is now to the new shape.
            for mask in [l.fillMask, l.sweepMask] {
                if animate, let current = mask.presentation()?.path ?? mask.path, current != r.path {
                    let anim = CABasicAnimation(keyPath: "path")
                    anim.fromValue = current
                    anim.toValue = r.path
                    anim.duration = Self.easeDuration
                    anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    mask.add(anim, forKey: "path")
                }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                mask.path = r.path
                CATransaction.commit()
            }
            updateSweeps(l, ribbon: r, animate: animate)
            updateLabel(l, ribbon: r, animate: animate)
        }
    }

    /// Watt label inside the ribbon, moving with it on the same ease. Labels
    /// drawn by SwiftUI on the glass card re-rasterised every animation frame
    /// on the CPU (20–40 % of a core with the Dashboard open).
    private func updateLabel(_ l: Layers, ribbon r: RibbonLayerView.Ribbon, animate: Bool) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let text = PowerFormat.watts(r.watts)
        let size = (text as NSString).size(withAttributes: [.font: font])
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.label.contentsScale = window?.backingScaleFactor ?? 2
        l.label.font = font
        l.label.fontSize = 13
        l.label.foregroundColor = NSColor.labelColor.cgColor
        l.label.alignmentMode = .center
        l.label.bounds = CGRect(x: 0, y: 0, width: ceil(size.width) + 4, height: ceil(size.height))
        l.label.string = text
        l.label.isHidden = !r.showsLabel
        CATransaction.commit()
        if animate, l.label.position != r.labelCenter {
            let anim = CABasicAnimation(keyPath: "position")
            anim.fromValue = NSValue(point: l.label.presentation()?.position ?? l.label.position)
            anim.toValue = NSValue(point: r.labelCenter)
            anim.duration = Self.easeDuration
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            l.label.add(anim, forKey: "position")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.label.position = r.labelCenter
        CATransaction.commit()
    }

    // SwiftUI hands over the ribbons before this view has been laid out, so
    // sizes are applied again whenever the view's own size settles.
    override func layout() {
        super.layout()
        applyFrames()
    }

    private func applyFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = max(bounds.width, 1)
        for (r, l) in zip(current, items) {
            l.fill.frame = bounds
            l.fill.colors = [r.from.withAlphaComponent(0.42).cgColor, r.to.withAlphaComponent(0.42).cgColor]
            l.fill.startPoint = CGPoint(x: r.x0 / w, y: 0.5)
            l.fill.endPoint = CGPoint(x: r.x1 / w, y: 0.5)
            l.sweepHost.frame = bounds
            l.fillMask.frame = bounds
            l.sweepMask.frame = bounds
        }
        CATransaction.commit()
    }

    private func makeLayers(in root: CALayer) -> Layers {
        let l = Layers()
        l.fill.mask = l.fillMask
        root.addSublayer(l.fill)
        l.sweepHost.mask = l.sweepMask
        root.addSublayer(l.sweepHost)
        for s in l.sweeps {
            s.startPoint = CGPoint(x: 0, y: 0.5)
            s.endPoint = CGPoint(x: 1, y: 0.5)
            s.colors = [NSColor.white.withAlphaComponent(0).cgColor,
                        NSColor.white.withAlphaComponent(0.55).cgColor,
                        NSColor.white.withAlphaComponent(0).cgColor]
            s.locations = [0, 0.5, 1]
            l.sweepHost.addSublayer(s)
        }
        root.addSublayer(l.label)
        return l
    }

    /// Two soft bands travel left to right, half a cycle apart; faster with
    /// more power. Animations restart only when the speed or span changes
    /// noticeably, so a new reading doesn't make them jump.
    private func updateSweeps(_ l: Layers, ribbon r: RibbonLayerView.Ribbon, animate: Bool) {
        let active = animate && r.watts > FlowGraph.threshold
        l.sweepHost.isHidden = !active
        guard active else {
            l.sweeps.forEach { $0.removeAllAnimations() }
            l.duration = 0
            return
        }
        let span = r.x1 - r.x0
        let glow = max(56, span * 0.32)
        let speed = 0.22 + min(0.5, r.watts / 90)           // cycles per second
        let duration = 1 / speed
        let height = r.bottom - r.top + 8
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for s in l.sweeps {
            s.bounds = CGRect(x: 0, y: 0, width: glow, height: height)
            s.position.y = (r.top + r.bottom) / 2
        }
        CATransaction.commit()

        let spanChanged = abs(l.span.0 - r.x0) > 1 || abs(l.span.1 - r.x1) > 1
        guard spanChanged || l.duration == 0 || abs(l.duration - duration) / l.duration > 0.2 else { return }
        l.duration = duration
        l.span = (r.x0, r.x1)
        let now = CACurrentMediaTime()
        for (k, s) in l.sweeps.enumerated() {
            let move = CABasicAnimation(keyPath: "position.x")
            move.fromValue = r.x0 - glow / 2
            move.toValue = r.x1 + glow / 2
            // Fade in and out at the ends so the band enters and leaves softly.
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.2, 0.8, 1]
            let group = CAAnimationGroup()
            group.animations = [move, fade]
            group.duration = duration
            group.repeatCount = .infinity
            group.beginTime = now - duration * Double(k) / Double(l.sweeps.count)
            group.timingFunction = CAMediaTimingFunction(name: .linear)
            s.add(group, forKey: "sweep")
        }
    }
}
