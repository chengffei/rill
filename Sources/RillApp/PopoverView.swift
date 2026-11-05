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
                    Label("打开 Dashboard", systemImage: "chart.xyaxis.line")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            } else {
                Text("这台 Mac 没有读到电池")
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        }
        .padding(14)
        .frame(width: 360)
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
                Text("\(PowerFormat.duration(minutes: m))充满")
                    .font(.system(size: 12)).foregroundStyle(Palette.caption)
            } else if let m = s.minutesToEmpty {
                Text("剩余 \(PowerFormat.duration(minutes: m))")
                    .font(.system(size: 12)).foregroundStyle(Palette.caption)
            }
        }
    }

    private func stateText(_ s: PowerSnapshot) -> String {
        switch s.state {
        case .charging: return "充电中"
        case .full: return "已充满"
        case .paused: return "暂停充电"
        case .onBattery: return "使用电池"
        case .assisting: return "充电器不够，电池补电"
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
            out.append(Point(id: i * 3, date: s.date, watts: s.inputWatts, series: "输入"))
            out.append(Point(id: i * 3 + 1, date: s.date, watts: s.systemWatts, series: "电脑"))
            out.append(Point(id: i * 3 + 2, date: s.date, watts: s.batteryWatts, series: "电池"))
        }
        return out
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("近 10 分钟")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                if let avg = model.history.averageSystemWatts, let peak = model.history.peakSystemWatts {
                    Text("电脑平均 \(PowerFormat.watts(avg))，峰值 \(PowerFormat.watts(peak))")
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
                "输入": StrokeStyle(lineWidth: 1.6, dash: [4, 3]),
                "电脑": StrokeStyle(lineWidth: 1.6),
                "电池": StrokeStyle(lineWidth: 1.6),
            ])
            .chartForegroundStyleScale(["输入": Palette.input, "电脑": Palette.system, "电池": Palette.charge])
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
                row("充电器", name)
                if let v = s.adapterNegotiatedVolts, let a = s.adapterNegotiatedAmps {
                    let rated = s.adapterRatedWatts.map { "，\($0) W" } ?? ""
                    row("协商", String(format: "%.1f V × %.2f A", v, a) + rated)
                }
                if let v = s.inputVolts, let a = s.inputAmps {
                    row("实际输入", String(format: "%.2f V × %.2f A", v, a))
                }
                row("转换损耗", PowerFormat.watts(s.lossWatts))
                Divider().padding(.vertical, 2)
            }
            row("电池", String(format: "%.2f V × %.2f A", s.batteryVolts, s.batteryAmps))
            if let h = s.health, let full = s.fullChargeCapacity, let design = s.designCapacity {
                row("健康度", String(format: "%.0f%%", h * 100) + "（\(full) / \(design) mAh）")
            }
            if let t = s.temperature { row("电池温度", String(format: "%.1f °C", t)) }
            if let c = s.cycleCount { row("循环次数", "\(c)") }
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
