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
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.045)))
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
        case .adapter: return L("充电器", "Charger")
        case .mac: return L("电脑", "Mac")
        case .battery: return showsWatts ? L("电池", "Battery") : (node.watts > FlowGraph.threshold ? L("充入电池", "Into Battery") : L("电池", "Battery"))
        }
    }
}

/// Geometry for the flow, a true Sankey: one scale turns watts into points
/// for every tile and ribbon, so a tile's height is the power through it and
/// a ribbon keeps the same thickness from end to end. The charger tile is the
/// 100 % bar; the ribbons leaving it split its height by share (2026-11-05,
/// Felix: the old trunk narrowed to 60 % and the tiles ignored the scale).
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

    /// Tiles never get shorter than this, so icon and label fit; an idle node
    /// (no flow) gets exactly this.
    static let minTile: CGFloat = 46
    static let gap: CGFloat = 8

    init(graph: FlowGraph, size: CGSize) {
        let tileWidth: CGFloat = min(84, size.width * 0.24)
        let sinkWidth: CGFloat = min(76, size.width * 0.21)
        let H = size.height
        let w = graph.links.map { CGFloat(max($0.watts, 0)) }

        // Flow through each node is the sum of its links, so both ends of
        // every ribbon match the tiles they touch.
        let sourceFlow = graph.sources.indices.map { n in graph.links.indices.filter { graph.links[$0].from == n }.map { w[$0] }.reduce(0, +) }
        let sinkFlow = graph.sinks.indices.map { n in graph.links.indices.filter { graph.links[$0].to == n }.map { w[$0] }.reduce(0, +) }

        // One scale for both columns: the largest that lets each fit.
        let k = min(Self.scale(sourceFlow, height: H), Self.scale(sinkFlow, height: H))
        sourceFrames = Self.stack(sourceFlow, k: k, x: 0, width: tileWidth, height: H)
        sinkFrames = Self.stack(sinkFlow, k: k, x: size.width - sinkWidth, width: sinkWidth, height: H)

        // Each node's links stack inside it, k·watts thick, centred in the
        // tile (a tile lifted to the minimum is taller than its flow).
        func ends(_ frames: [CGRect], _ flow: [CGFloat], key: (FlowGraph.Link) -> Int) -> [Int: (CGFloat, CGFloat)] {
            var out: [Int: (CGFloat, CGFloat)] = [:]
            for (n, frame) in frames.enumerated() {
                var y = frame.midY - k * flow[n] / 2
                for i in graph.links.indices where key(graph.links[i]) == n {
                    out[i] = (y, y + k * w[i])
                    y += k * w[i]
                }
            }
            return out
        }
        let left = ends(sourceFrames, sourceFlow, key: \.from)
        let right = ends(sinkFrames, sinkFlow, key: \.to)
        let x0 = tileWidth - 2, x1 = size.width - sinkWidth + 2
        ribbons = graph.links.indices.map { i in
            let (t0, b0) = left[i] ?? (0, 0)
            let (t1, b1) = right[i] ?? (0, 0)
            // Pull ribbons in a little so neighbours read as separate bands.
            let inset: CGFloat = min(1.5, (b0 - t0) / 4)
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

    private static func isActive(_ f: CGFloat) -> Bool { f > CGFloat(FlowGraph.threshold) }

    /// Largest points-per-watt at which a column fits in `height`: every
    /// tile is max(k·flow, minTile), idle tiles are minTile.
    static func scale(_ flow: [CGFloat], height: CGFloat) -> CGFloat {
        var avail = height - gap * CGFloat(max(flow.count - 1, 0))
        var open = flow.indices.filter { isActive(flow[$0]) }
        avail -= minTile * CGFloat(flow.count - open.count)
        // Tiles whose share would fall under the minimum are fixed at it;
        // the rest split what's left. Repeat until nothing more drops out.
        while true {
            let total = open.map { flow[$0] }.reduce(0, +)
            guard total > 0, avail > 0 else { return total > 0 ? 0.0001 : .greatestFiniteMagnitude }
            let k = avail / total
            let small = open.filter { k * flow[$0] < minTile }
            if small.isEmpty || small.count == open.count { return k }
            avail -= minTile * CGFloat(small.count)
            open.removeAll { small.contains($0) }
        }
    }

    /// Stacks a column of tiles at scale k, centred vertically when the
    /// column is shorter than the view (the other column set the scale).
    private static func stack(_ flow: [CGFloat], k: CGFloat, x: CGFloat, width: CGFloat, height: CGFloat) -> [CGRect] {
        guard !flow.isEmpty else { return [] }
        let finiteK = k.isFinite && k < .greatestFiniteMagnitude ? k : 0
        let heights = flow.map { isActive($0) ? max(finiteK * $0, minTile) : minTile }
        let total = heights.reduce(0, +) + gap * CGFloat(flow.count - 1)
        var y = max(0, (height - total) / 2)
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
