import Charts
import RillCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: PowerModel
    @State private var range: ChartRange = .hour6
    /// ImageRenderer can't draw ScrollView content; snapshots turn it off.
    var scrolls = true

    var body: some View {
        Group {
            if scrolls { ScrollView { content } } else { content }
        }
        .frame(minWidth: 920, minHeight: 640)
        .background(Color.white)
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 20) {
                if let s = model.snapshot {
                    hero(s)
                    HStack(alignment: .top, spacing: 16) {
                        batteryCard(s)
                        adapterCard(s)
                        todayCard
                    }
                    powerCard
                    HStack(alignment: .top, spacing: 16) {
                        SeriesCard(title: "电量", unit: "%", records: visibleRecords, color: Palette.charge,
                                   domain: 0...100, value: { Double($0.percent) })
                        SeriesCard(title: "电池温度", unit: "°C", records: visibleRecords, color: Palette.discharge,
                                   domain: nil, value: { $0.temp })
                    }
                } else {
                    Text("这台 Mac 没有读到电池")
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(28)
    }

    // MARK: Hero

    private func hero(_ s: PowerSnapshot) -> some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(s.percent)%")
                    .font(.system(size: 48, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.text)
                Text(stateText(s))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                if let m = s.minutesToFull {
                    Text("\(PowerFormat.duration(minutes: m))充满").font(.system(size: 13)).foregroundStyle(Palette.caption)
                } else if let m = s.minutesToEmpty {
                    Text("剩余 \(PowerFormat.duration(minutes: m))").font(.system(size: 13)).foregroundStyle(Palette.caption)
                }
            }
            .frame(width: 200, alignment: .leading)
            FlowView(snapshot: s)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Cards

    private func batteryCard(_ s: PowerSnapshot) -> some View {
        Card(title: "电池") {
            Row("电压与电流", String(format: "%.2f V × %.2f A", s.batteryVolts, s.batteryAmps))
            Row("功率", (s.batteryWatts >= 0 ? "充入 " : "放出 ") + PowerFormat.watts(s.batteryWatts))
            if let t = s.temperature { Row("温度", String(format: "%.1f °C", t)) }
            if let h = s.health { Row("健康度", String(format: "%.0f%%", h * 100)) }
            if let full = s.fullChargeCapacity, let design = s.designCapacity {
                Row("容量", "\(full) / \(design) mAh")
            }
            if let c = s.cycleCount { Row("循环次数", "\(c)") }
        }
    }

    private func adapterCard(_ s: PowerSnapshot) -> some View {
        Card(title: "充电器") {
            if let name = s.adapterName {
                Row("型号", name)
                if let w = s.adapterRatedWatts { Row("额定", "\(w) W") }
                if let v = s.adapterNegotiatedVolts, let a = s.adapterNegotiatedAmps {
                    Row("协商", String(format: "%.1f V × %.2f A", v, a))
                }
                Row("实际输入", PowerFormat.watts(s.inputWatts))
                if let rated = s.adapterRatedWatts, rated > 0 {
                    Row("利用率", String(format: "%.0f%%", s.inputWatts / Double(rated) * 100))
                }
                Row("转换损耗", PowerFormat.watts(s.lossWatts))
            } else {
                Text("未接充电器").font(.system(size: 13)).foregroundStyle(Palette.caption)
            }
        }
    }

    private var todayCard: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let e = EnergyStats(records: model.minutes.filter { $0.t >= start })
        return Card(title: "今日用电") {
            Row("充电器供电", String(format: "%.1f Wh", e.inputWh))
            Row("电脑用电", String(format: "%.1f Wh", e.systemWh))
            Row("充入电池", String(format: "%.1f Wh", e.chargedWh))
            Row("电池放出", String(format: "%.1f Wh", e.dischargedWh))
            if let avg = e.averageSystem { Row("平均负载", PowerFormat.watts(avg)) }
            if let peak = e.peakSystem { Row("最高分钟负载", PowerFormat.watts(peak)) }
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
                Text("功率").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
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
        .background(RoundedRectangle(cornerRadius: 18).fill(Palette.panel))
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
}

enum ChartRange: String, CaseIterable, Identifiable {
    case hour1, hour6, hour24, day7
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hour1: return "1 小时"
        case .hour6: return "6 小时"
        case .hour24: return "24 小时"
        case .day7: return "7 天"
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
        .background(RoundedRectangle(cornerRadius: 18).fill(Palette.panel))
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
            [Point(id: "i\(r.t.timeIntervalSince1970)", t: r.t, w: r.input, series: "输入"),
             Point(id: "s\(r.t.timeIntervalSince1970)", t: r.t, w: r.system, series: "电脑"),
             Point(id: "b\(r.t.timeIntervalSince1970)", t: r.t, w: r.battery, series: "电池")]
        }
    }

    private var nearest: MinuteRecord? {
        guard let selected else { return nil }
        return records.min { abs($0.t.timeIntervalSince(selected)) < abs($1.t.timeIntervalSince(selected)) }
    }

    var body: some View {
        if records.count < 2 {
            Text("还没有记录。Rill 每分钟存一条，开着就会积累。")
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
                                Text("输入 \(PowerFormat.watts(r.input))")
                                Text("电脑 \(PowerFormat.watts(r.system))")
                                Text((r.battery >= 0 ? "充入 " : "放出 ") + PowerFormat.watts(r.battery))
                            }
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Palette.text)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                        }
                }
            }
            .chartForegroundStyleScale(["输入": Palette.input, "电脑": Palette.system, "电池": Palette.charge])
            .chartLineStyleScale([
                "输入": StrokeStyle(lineWidth: 1.6, dash: [4, 3]),
                "电脑": StrokeStyle(lineWidth: 1.8),
                "电池": StrokeStyle(lineWidth: 1.6),
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
                Text("还没有记录").font(.system(size: 13)).foregroundStyle(Palette.caption)
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
        .background(RoundedRectangle(cornerRadius: 18).fill(Palette.panel))
    }
}
