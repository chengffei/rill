import RillCore
import SwiftUI

/// Sankey-style power flow: sources on the left, the Mac and the battery on
/// the right, ribbons as thick as the power they carry, with light sweeping
/// along them and sizes easing between readings (ribbons in Core Animation,
/// see RibbonLayerView). Replaces the earlier in-line "charger → Mac → battery" row,
/// which drew the battery as if it were fed through the Mac.
struct FlowView: View {
    let snapshot: PowerSnapshot
    var height: CGFloat = 150

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let graph = FlowGraph(snapshot)
        GeometryReader { geo in
            let layout = FlowLayout(graph: graph, size: geo.size)
            ZStack(alignment: .topLeading) {
                RibbonLayerView(ribbons: ribbons(layout, graph: graph), reduceMotion: reduceMotion)
                ForEach(Array(layout.sourceFrames.enumerated()), id: \.offset) { i, frame in
                    NodeTile(node: graph.sources[i], showsWatts: true, percent: snapshot.percent)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
                ForEach(Array(layout.sinkFrames.enumerated()), id: \.offset) { i, frame in
                    NodeTile(node: graph.sinks[i], showsWatts: false, percent: snapshot.percent)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            // No SwiftUI animation here: inside glass cards every animated
            // frame re-rasterises text on the CPU. Ribbons and their labels
            // ease in Core Animation; tiles switch at once.
        }
        .frame(height: height)
        .padding(10)
    }

    private func ribbons(_ layout: FlowLayout, graph: FlowGraph) -> [RibbonLayerView.Ribbon] {
        graph.links.enumerated().map { i, link in
            let r = layout.ribbons[i]
            return RibbonLayerView.Ribbon(
                path: r.path.cgPath, x0: r.x0, x1: r.x1,
                top: min(r.top0, r.top1), bottom: max(r.bottom0, r.bottom1),
                from: NSColor(Self.color(graph.sources[link.from].role)),
                to: NSColor(Self.color(graph.sinks[link.to].role)),
                watts: link.watts,
                labelCenter: r.center(at: 0.5),
                showsLabel: r.labelThickness >= 18)
        }
    }

    static func color(_ role: FlowGraph.Role) -> Color {
        switch role {
        case .adapter: return Palette.input
        case .battery: return Palette.charge
        case .mac: return Palette.system
        }
    }
}

private struct NodeTile: View {
    let node: FlowGraph.Node
    let showsWatts: Bool
    let percent: Int

    var body: some View {
        let idle = node.watts <= FlowGraph.threshold
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(idle && node.role != .adapter ? Color.secondary : FlowView.color(node.role))
            if showsWatts {
                Text(PowerFormat.watts(node.watts))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.primary)
                    
            }
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.06)))
    }

    private var symbol: String {
        switch node.role {
        case .adapter: return "powerplug.portrait.fill"
        case .mac: return "laptopcomputer"
        case .battery:
            switch percent {
            case 88...: return "battery.100percent"
            case 63..<88: return "battery.75percent"
            case 38..<63: return "battery.50percent"
            case 13..<38: return "battery.25percent"
            default: return "battery.0percent"
            }
        }
    }

    private var title: String {
        switch node.role {
        case .adapter: return "充电器"
        case .mac: return "电脑"
        case .battery: return showsWatts ? "电池" : (node.watts > FlowGraph.threshold ? "充入电池" : "电池")
        }
    }
}

/// Geometry for the flow: node tiles stacked in two columns, ribbons whose
/// thickness at each end is their share of the node they touch.
struct FlowLayout {
    struct Ribbon {
        let path: Path
        let x0: CGFloat, x1: CGFloat
        let top0: CGFloat, bottom0: CGFloat, top1: CGFloat, bottom1: CGFloat
        /// Mean thickness; labels only go inside ribbons thick enough to hold them.
        var labelThickness: CGFloat { ((bottom0 - top0) + (bottom1 - top1)) / 2 }

        /// Point on the ribbon's centre line at t in 0...1.
        func center(at t: Double) -> CGPoint {
            let y0 = (top0 + bottom0) / 2, y1 = (top1 + bottom1) / 2
            return FlowLayout.bezier(x0: x0, y0: y0, x1: x1, y1: y1, t: CGFloat(t))
        }
    }

    let sourceFrames: [CGRect]
    let sinkFrames: [CGRect]
    let ribbons: [Ribbon]

    init(graph: FlowGraph, size: CGSize) {
        let tileWidth: CGFloat = min(84, size.width * 0.24)
        let sinkWidth: CGFloat = min(76, size.width * 0.21)
        let gap: CGFloat = 8
        sourceFrames = Self.stack(graph.sources, x: 0, width: tileWidth, height: size.height, gap: gap)
        sinkFrames = Self.stack(graph.sinks, x: size.width - sinkWidth, width: sinkWidth, height: size.height, gap: gap)

        // Each node's links share its height in proportion to their watts.
        // On the trunk side (fewer nodes) the bundle is narrowed and centred,
        // so ribbons branch out from it like the reference Sankey; the other
        // side fills each node.
        func segments(nodeFrames: [CGRect], key: (FlowGraph.Link) -> Int, trunk: Bool) -> [Int: (CGFloat, CGFloat)] {
            var out: [Int: (CGFloat, CGFloat)] = [:]
            for (n, frame) in nodeFrames.enumerated() {
                let mine = graph.links.enumerated().filter { key($0.element) == n }
                let total = mine.map { max($0.element.watts, 0.01) }.reduce(0, +)
                let usable = trunk ? frame.height * 0.6 : frame.height - 6
                var y = frame.midY - usable / 2
                for (i, link) in mine {
                    let h = usable * CGFloat(max(link.watts, 0.01) / total)
                    out[i] = (y, y + h)
                    y += h
                }
            }
            return out
        }
        let sourceIsTrunk = graph.sources.count <= graph.sinks.count
        let left = segments(nodeFrames: sourceFrames, key: \.from, trunk: sourceIsTrunk)
        let right = segments(nodeFrames: sinkFrames, key: \.to, trunk: !sourceIsTrunk)
        let x0 = tileWidth - 2, x1 = size.width - sinkWidth + 2
        ribbons = graph.links.indices.map { i in
            let (t0, b0) = left[i] ?? (0, 0)
            let (t1, b1) = right[i] ?? (0, 0)
            // Pull ribbons in a little so neighbours read as separate bands.
            let inset: CGFloat = 1.5
            let a0 = t0 + inset, c0 = b0 - inset, a1 = t1 + inset, c1 = b1 - inset
            var p = Path()
            p.move(to: CGPoint(x: x0, y: a0))
            Self.curve(&p, x0: x0, y0: a0, x1: x1, y1: a1)
            p.addLine(to: CGPoint(x: x1, y: c1))
            Self.curve(&p, x0: x1, y0: c1, x1: x0, y1: c0)
            p.closeSubpath()
            return Ribbon(path: p, x0: x0, x1: x1, top0: a0, bottom0: c0, top1: a1, bottom1: c1)
        }
    }

    /// Stacks node tiles in a column; busier nodes get more height, every
    /// tile at least 46 pt so its icon and label fit.
    private static func stack(_ nodes: [FlowGraph.Node], x: CGFloat, width: CGFloat, height: CGFloat, gap: CGFloat) -> [CGRect] {
        guard !nodes.isEmpty else { return [] }
        let usable = height - gap * CGFloat(nodes.count - 1)
        let minH: CGFloat = 46
        let total = nodes.map { max($0.watts, 0) }.reduce(0, +)
        var heights = nodes.map { n -> CGFloat in
            total > 0 ? usable * CGFloat(max(n.watts, 0) / total) : usable / CGFloat(nodes.count)
        }
        // Lift small tiles to the minimum, taking the difference from the others.
        let short = heights.indices.filter { heights[$0] < minH }
        if !short.isEmpty, short.count < heights.count {
            let need = short.map { minH - heights[$0] }.reduce(0, +)
            let others = heights.indices.filter { !short.contains($0) }
            let pool = others.map { heights[$0] }.reduce(0, +)
            for i in short { heights[i] = minH }
            for i in others { heights[i] -= need * heights[i] / pool }
        }
        var y: CGFloat = 0
        return heights.map { h in
            defer { y += h + gap }
            return CGRect(x: x, y: y, width: width, height: h)
        }
    }

    private static func curve(_ p: inout Path, x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat) {
        let mx = (x0 + x1) / 2
        p.addCurve(to: CGPoint(x: x1, y: y1), control1: CGPoint(x: mx, y: y0), control2: CGPoint(x: mx, y: y1))
    }

    static func bezier(x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat, t: CGFloat) -> CGPoint {
        let mx = (x0 + x1) / 2
        let u = 1 - t
        let x = u * u * u * x0 + 3 * u * u * t * mx + 3 * u * t * t * mx + t * t * t * x1
        let y = u * u * u * y0 + 3 * u * u * t * y0 + 3 * u * t * t * y1 + t * t * t * y1
        return CGPoint(x: x, y: y)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
