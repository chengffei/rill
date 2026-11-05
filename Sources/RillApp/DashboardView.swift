import Charts
import RillCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: PowerModel
    var onOpenSettings: () -> Void
    @ObservedObject private var settings = AppSettings.shared
    @State private var range: ChartRange = .hour6
    @State private var scroller = GlassScroller.State()
    @State private var scrollPosition = ScrollPosition(edge: .top)
    /// ImageRenderer can't draw ScrollView content; snapshots turn it off.
    var scrolls = true

    var body: some View {
        Group {
            if scrolls {
                // The system scroller showed as a thick grey legacy bar
                // (Felix, 2026-11-05); a glass thumb replaces it.
                ScrollView { content.id(settings.language) }
                    .scrollIndicators(.never)
                    .scrollPosition($scrollPosition)
                    .onScrollGeometryChange(for: GlassScroller.Metrics.self, of: GlassScroller.Metrics.init) { _, m in
                        scroller.update(m)
                    }
                    .overlay(alignment: .topTrailing) {
                        GlassScroller(state: scroller, position: $scrollPosition)
                    }
            } else {
                content
            }
        }
        .frame(minWidth: 920, minHeight: 640)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                }
                .help(L("设置", "Settings"))
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private var content: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(alignment: .leading, spacing: 20) {
                if let s = model.snapshot {
                    hero(s)
                    HStack(alignment: .top, spacing: 16) {
                        batteryCard(s)
                        adapterCard(s)
                        todayCard
                    }
                    EnergyAppsCard(top: model.topApps, heavy: model.heavyApps, measured: model.energyMeasured)
                    powerCard
                    HStack(alignment: .top, spacing: 16) {
                        SeriesCard(title: L("电量", "Battery Level"), unit: "%", records: visibleRecords, color: Palette.charge,
                                   domain: 0...100, value: { Double($0.percent) })
                        SeriesCard(title: L("电池温度", "Battery Temperature"), unit: "°C", records: visibleRecords, color: Palette.discharge,
                                   domain: nil, value: { $0.temp })
                    }
                } else {
                    Text(L("这台 Mac 没有读到电池", "No battery found on this Mac"))
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            // Clears the transparent title bar and its traffic lights.
            .padding(.top, 44)
        }
    }

    // MARK: Hero

    /// Battery status and the power flow in one card, so the status no
    /// longer floats unanchored beside the flow (Felix, 2026-11-05).
    private func hero(_ s: PowerSnapshot) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                BatteryGauge(percent: s.percent, state: s.state)
                    .padding(.bottom, 6)
                Text("\(s.percent)%")
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.text)
                Text(stateText(s))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                if let m = s.minutesToFull {
                    Text(L("\(durationText(m))充满", "Full in \(durationText(m))"))
                        .font(.system(size: 12)).foregroundStyle(Palette.caption)
                } else if let m = s.minutesToEmpty {
                    Text(L("剩余 \(durationText(m))", "\(durationText(m)) left"))
                        .font(.system(size: 12)).foregroundStyle(Palette.caption)
                }
            }
            .frame(width: 170, alignment: .leading)
            .padding(.leading, 22)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 22)
            FlowView(snapshot: s, height: 170)
                .frame(maxWidth: .infinity)
                .padding(.leading, 6)
        }
        .glassCard()
    }

    // MARK: Cards

    private func batteryCard(_ s: PowerSnapshot) -> some View {
        Card(title: L("电池", "Battery")) {
            Row(L("电压与电流", "Voltage & Current"), String(format: "%.2f V × %.2f A", s.batteryVolts, s.batteryAmps))
            Row(L("功率", "Power"), (s.batteryWatts >= 0 ? L("充入 ", "In ") : L("放出 ", "Out ")) + PowerFormat.watts(s.batteryWatts))
            if let t = s.temperature { Row(L("温度", "Temperature"), String(format: "%.1f °C", t)) }
            if let h = s.health { Row(L("健康度", "Health"), String(format: "%.0f%%", h * 100)) }
            if let full = s.fullChargeCapacity, let design = s.designCapacity {
                Row(L("容量", "Capacity"), "\(full) / \(design) mAh")
            }
            if let c = s.cycleCount { Row(L("循环次数", "Cycle Count"), "\(c)") }
        }
    }

    private func adapterCard(_ s: PowerSnapshot) -> some View {
        Card(title: L("充电器", "Charger")) {
            if let name = s.adapterName {
                Row(L("型号", "Model"), name)
                if let w = s.adapterRatedWatts { Row(L("额定", "Rated"), "\(w) W") }
                if let v = s.adapterNegotiatedVolts, let a = s.adapterNegotiatedAmps {
                    Row(L("协商", "Negotiated"), String(format: "%.1f V × %.2f A", v, a))
                }
                Row(L("实际输入", "Actual Input"), PowerFormat.watts(s.inputWatts))
                if let rated = s.adapterRatedWatts, rated > 0 {
                    Row(L("利用率", "Utilization"), String(format: "%.0f%%", s.inputWatts / Double(rated) * 100))
                }
                Row(L("转换损耗", "Conversion Loss"), PowerFormat.watts(s.lossWatts))
            } else {
                Text(L("未接充电器", "No charger connected")).font(.system(size: 13)).foregroundStyle(Palette.caption)
            }
        }
    }

    private var todayCard: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let e = EnergyStats(records: model.minutes.filter { $0.t >= start })
        return Card(title: L("今日用电", "Today")) {
            Row(L("充电器供电", "From Charger"), String(format: "%.1f Wh", e.inputWh))
            Row(L("电脑用电", "Used by Mac"), String(format: "%.1f Wh", e.systemWh))
            Row(L("充入电池", "Into Battery"), String(format: "%.1f Wh", e.chargedWh))
            Row(L("电池放出", "From Battery"), String(format: "%.1f Wh", e.dischargedWh))
            if let avg = e.averageSystem { Row(L("平均负载", "Average Load"), PowerFormat.watts(avg)) }
            if let peak = e.peakSystem { Row(L("最高分钟负载", "Peak Minute Load"), PowerFormat.watts(peak)) }
        }
    }

    // MARK: Power chart

    private var visibleRecords: [MinuteRecord] {
        let since = Date().addingTimeInterval(-range.seconds)
        return Downsample.buckets(model.minutes.filter { $0.t >= since }, maxPoints: 360)
    }

    private var powerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("功率", "Power")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Picker("", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
            }
            PowerChart(records: visibleRecords)
                .frame(height: 260)
        }
        .padding(18)
        .glassCard()
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
}

enum ChartRange: String, CaseIterable, Identifiable {
    case hour1, hour6, hour24, day7
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hour1: return L("1 小时", "1 Hour")
        case .hour6: return L("6 小时", "6 Hours")
        case .hour24: return L("24 小时", "24 Hours")
        case .day7: return L("7 天", "7 Days")
        }
    }
    var seconds: TimeInterval {
        switch self {
        case .hour1: return 3600
        case .hour6: return 6 * 3600
        case .hour24: return 86400
        case .day7: return 7 * 86400
        }
    }
}

// MARK: - Building blocks

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                .padding(.bottom, 3)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .glassCard()
    }
}

private struct Row: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Palette.caption)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(Palette.text).monospacedDigit().lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 13))
    }
}

private struct PowerChart: View {
    let records: [MinuteRecord]
    @State private var selected: Date?

    private struct Point: Identifiable {
        let id: String
        let t: Date
        let w: Double
        let series: String
    }

    private var points: [Point] {
        records.flatMap { r in
            [Point(id: "i\(r.t.timeIntervalSince1970)", t: r.t, w: r.input, series: L("输入", "Input")),
             Point(id: "s\(r.t.timeIntervalSince1970)", t: r.t, w: r.system, series: L("电脑", "Mac")),
             Point(id: "b\(r.t.timeIntervalSince1970)", t: r.t, w: r.battery, series: L("电池", "Battery"))]
        }
    }

    private var nearest: MinuteRecord? {
        guard let selected else { return nil }
        return records.min { abs($0.t.timeIntervalSince(selected)) < abs($1.t.timeIntervalSince(selected)) }
    }

    var body: some View {
        if records.count < 2 {
            Text(L("还没有记录。Rill 每分钟存一条，开着就会积累。", "No history yet. Rill saves a reading every minute while it runs."))
                .font(.system(size: 13)).foregroundStyle(Palette.caption)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value("时间", p.t), y: .value("功率", p.w))
                        .foregroundStyle(by: .value("线", p.series))
                        .lineStyle(by: .value("线", p.series))
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("零", 0)).foregroundStyle(Color.black.opacity(0.15))
                if let r = nearest {
                    RuleMark(x: .value("选中", r.t))
                        .foregroundStyle(Color.black.opacity(0.25))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.t, format: .dateTime.month().day().hour().minute())
                                    .foregroundStyle(Palette.caption)
                                Text(L("输入 ", "Input ") + PowerFormat.watts(r.input))
                                Text(L("电脑 ", "Mac ") + PowerFormat.watts(r.system))
                                Text((r.battery >= 0 ? L("充入 ", "In ") : L("放出 ", "Out ")) + PowerFormat.watts(r.battery))
                            }
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Palette.text)
                            .padding(8)
                            .glassEffect(.regular, in: .rect(cornerRadius: 10))
                        }
                }
            }
            .chartForegroundStyleScale([L("输入", "Input"): Palette.input, L("电脑", "Mac"): Palette.system, L("电池", "Battery"): Palette.charge])
            .chartLineStyleScale([
                L("输入", "Input"): StrokeStyle(lineWidth: 1.6, dash: [4, 3]),
                L("电脑", "Mac"): StrokeStyle(lineWidth: 1.8),
                L("电池", "Battery"): StrokeStyle(lineWidth: 1.6),
            ])
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
                    AxisValueLabel { if let w = v.as(Double.self) { Text("\(Int(w)) W") } }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading)
        }
    }
}

private struct SeriesCard: View {
    let title: String
    let unit: String
    let records: [MinuteRecord]
    let color: Color
    let domain: ClosedRange<Double>?
    let value: (MinuteRecord) -> Double?

    var body: some View {
        let pts = records.compactMap { r in value(r).map { (r.t, $0) } }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                if let last = pts.last?.1 {
                    Text(String(format: unit == "%" ? "%.0f %@" : "%.1f %@", last, unit))
                        .font(.system(size: 13).monospacedDigit()).foregroundStyle(Palette.secondary)
                }
            }
            if pts.count < 2 {
                Text(L("还没有记录", "No history yet")).font(.system(size: 13)).foregroundStyle(Palette.caption)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                let chart = Chart {
                    ForEach(pts, id: \.0) { p in
                        // A filled area always reaches 0, which would flatten
                        // the temperature line; only the fixed 0–100 % chart fills.
                        if domain != nil {
                            AreaMark(x: .value("时间", p.0), y: .value(title, p.1))
                                .foregroundStyle(color.opacity(0.12))
                                .interpolationMethod(.monotone)
                        }
                        LineMark(x: .value("时间", p.0), y: .value(title, p.1))
                            .foregroundStyle(color)
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
                        AxisValueLabel()
                    }
                }
                .frame(height: 140)
                if let domain {
                    chart.chartYScale(domain: domain)
                } else {
                    chart.chartYScale(domain: .automatic(includesZero: false))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}
