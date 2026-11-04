import RillCore
import SwiftUI

/// Charger → Mac ⇄ battery, with moving dashes where power flows.
struct FlowView: View {
    let snapshot: PowerSnapshot

    var body: some View {
        HStack(spacing: 0) {
            node(symbol: "powerplug.fill", title: "充电器",
                 watts: snapshot.externalConnected ? snapshot.inputWatts : nil,
                 tint: Palette.input)
            FlowLink(direction: snapshot.inputWatts > 0.3 ? .forward : .idle, color: Palette.input)
            node(symbol: "laptopcomputer", title: "电脑", watts: snapshot.systemWatts, tint: Palette.system)
            FlowLink(direction: batteryDirection, color: batteryColor)
            node(symbol: batterySymbol, title: batteryTitle,
                 watts: abs(snapshot.batteryWatts) > 0.05 ? abs(snapshot.batteryWatts) : 0,
                 tint: batteryColor)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
    }

    private var batteryDirection: FlowLink.Direction {
        if snapshot.batteryWatts > 0.3 { return .forward }
        if snapshot.batteryWatts < -0.3 { return .backward }
        return .idle
    }

    private var batteryColor: Color {
        snapshot.batteryWatts < -0.3 ? Palette.discharge : Palette.charge
    }

    private var batteryTitle: String {
        if snapshot.batteryWatts > 0.3 { return "充入电池" }
        if snapshot.batteryWatts < -0.3 { return "电池放电" }
        return "电池"
    }

    private var batterySymbol: String {
        switch snapshot.percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private func node(symbol: String, title: String, watts: Double?, tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(watts == nil ? Palette.caption : tint)
                .frame(height: 24)
            Text(watts.map(PowerFormat.watts) ?? "未接")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(watts == nil ? Palette.caption : Palette.text)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Palette.caption)
        }
        .frame(width: 86)
    }
}

struct FlowLink: View {
    enum Direction { case forward, backward, idle }
    let direction: Direction
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: direction == .idle)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(t.truncatingRemainder(dividingBy: 1)) * 12
            Canvas { ctx, size in
                var path = Path()
                path.move(to: CGPoint(x: 2, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width - 2, y: size.height / 2))
                let active = direction != .idle
                ctx.stroke(path, with: .color(active ? color : Color.black.opacity(0.12)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round,
                                              dash: active ? [4, 8] : [],
                                              dashPhase: direction == .backward ? phase : -phase))
                guard active else { return }
                // Arrow head at the receiving end.
                let tipX = direction == .forward ? size.width - 2 : 2
                let back: CGFloat = direction == .forward ? -6 : 6
                var head = Path()
                head.move(to: CGPoint(x: tipX + back, y: size.height / 2 - 5))
                head.addLine(to: CGPoint(x: tipX, y: size.height / 2))
                head.addLine(to: CGPoint(x: tipX + back, y: size.height / 2 + 5))
                ctx.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
        .offset(y: -14)
    }
}
