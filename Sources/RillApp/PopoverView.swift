import Charts
import RillCore
import SwiftUI

enum Palette {
    // Semantic label colors: on Liquid Glass they pick up vibrancy and stay
    // legible over whatever is behind the panel; fixed greys did not.
    static let text = Color.primary
    static let secondary = Color.secondary
    static let caption = Color.secondary
    static let input = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let system = Color(red: 0.35, green: 0.34, blue: 0.84)
    static let charge = Color(red: 0.20, green: 0.70, blue: 0.35)
    static let discharge = Color(red: 1.0, green: 0.58, blue: 0.0)
}

struct PopoverView: View {
    @ObservedObject var model: PowerModel
    var onOpenDashboard: () -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        GlassEffectContainer(spacing: 12) {
        VStack(alignment: .leading, spacing: 12) {
            if let s = model.snapshot {
                header(s)
                FlowView(snapshot: s)
                    .glassCard()
                HeavyAppsRow(apps: model.heavyApps)
                    .glassCard()
                chart
                details(s)
                    .padding(14)
                    .glassCard()
                Button(action: onOpenDashboard) {
                    Label(L("打开 Dashboard", "Open Dashboard"), systemImage: "chart.xyaxis.line")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            } else {
                Text(L("这台 Mac 没有读到电池", "No battery found on this Mac"))
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        }
        .padding(14)
        .frame(width: 360)
        .id(settings.language)
        // A light wash under the cards: the popover's own glass over a dark
        // wallpaper made the whole panel read grey (2026-11-05).
        .background(Color(white: 0.98).opacity(0.72).ignoresSafeArea())
    }

    // MARK: Header

    private func header(_ s: PowerSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(s.percent)%")
                .font(.system(size: 28, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.text)
            Text(stateText(s))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.secondary)
            Spacer()
            if let m = s.minutesToFull {
                Text(L("\(durationText(m))充满", "Full in \(durationText(m))"))
                    .font(.system(size: 12)).foregroundStyle(Palette.caption)
            } else if let m = s.minutesToEmpty {
                Text(L("剩余 \(durationText(m))", "\(durationText(m)) left"))
                    .font(.system(size: 12)).foregroundStyle(Palette.caption)
            }
        }
    }

    private func stateText(_ s: PowerSnapshot) -> String {
        switch s.state {
        case .charging: return L("充电中", "Charging")
        case .full: return L("已充满", "Fully Charged")
        case .paused: return L("暂停充电", "Charging Paused")
        case .onBattery: return L("使用电池", "On Battery")
        case .assisting: return L("充电器不够，电池补电", "Battery assisting the charger")
        }
    }

    // MARK: Chart

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let watts: Double
        let series: String
    }

    private var points: [Point] {
        var out: [Point] = []
        for (i, s) in model.history.samples.enumerated() {
            out.append(Point(id: i * 3, date: s.date, watts: s.inputWatts, series: L("输入", "Input")))
            out.append(Point(id: i * 3 + 1, date: s.date, watts: s.systemWatts, series: L("电脑", "Mac")))
            out.append(Point(id: i * 3 + 2, date: s.date, watts: s.batteryWatts, series: L("电池", "Battery")))
        }
        return out
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("近 10 分钟", "Last 10 Minutes"))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                if let avg = model.history.averageSystemWatts, let peak = model.history.peakSystemWatts {
                    Text(L("电脑平均 \(PowerFormat.watts(avg))，峰值 \(PowerFormat.watts(peak))", "Mac average \(PowerFormat.watts(avg)), peak \(PowerFormat.watts(peak))"))
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Palette.caption)
                }
            }
            Chart(points) { p in
                LineMark(x: .value("时间", p.date), y: .value("功率", p.watts))
                    .foregroundStyle(by: .value("线", p.series))
                    .interpolationMethod(.monotone)
                    .lineStyle(by: .value("线", p.series))
            }
            .chartLineStyleScale([
                L("输入", "Input"): StrokeStyle(lineWidth: 1.6, dash: [4, 3]),
                L("电脑", "Mac"): StrokeStyle(lineWidth: 1.6),
                L("电池", "Battery"): StrokeStyle(lineWidth: 1.6),
            ])
            .chartForegroundStyleScale([L("输入", "Input"): Palette.input, L("电脑", "Mac"): Palette.system, L("电池", "Battery"): Palette.charge])
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
                    AxisValueLabel {
                        if let w = v.as(Double.self) { Text("\(Int(w)) W").font(.system(size: 10)) }
                    }
                }
            }
            .chartLegend(position: .bottom, spacing: 6)
            .frame(height: 120)
        }
        .padding(14)
        .glassCard()
    }

    // MARK: Details

    private func details(_ s: PowerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name = s.adapterName {
                row(L("充电器", "Charger"), name)
                if let v = s.adapterNegotiatedVolts, let a = s.adapterNegotiatedAmps {
                    let rated = s.adapterRatedWatts.map { L("，\($0) W", ", \($0) W") } ?? ""
                    row(L("协商", "Negotiated"), String(format: "%.1f V × %.2f A", v, a) + rated)
                }
                if let v = s.inputVolts, let a = s.inputAmps {
                    row(L("实际输入", "Actual Input"), String(format: "%.2f V × %.2f A", v, a))
                }
                row(L("转换损耗", "Conversion Loss"), PowerFormat.watts(s.lossWatts))
                Divider().padding(.vertical, 2)
            }
            row(L("电池", "Battery"), String(format: "%.2f V × %.2f A", s.batteryVolts, s.batteryAmps))
            if let h = s.health, let full = s.fullChargeCapacity, let design = s.designCapacity {
                row(L("健康度", "Health"), String(format: "%.0f%%", h * 100) + L("（\(full) / \(design) mAh）", " (\(full) / \(design) mAh)"))
            }
            if let t = s.temperature { row(L("电池温度", "Battery Temperature"), String(format: "%.1f °C", t)) }
            if let c = s.cycleCount { row(L("循环次数", "Cycle Count"), "\(c)") }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.caption)
            Spacer()
            Text(value).foregroundStyle(Palette.text).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}
