import Charts
import RillCore
import SwiftUI

/// The window's pages, in sidebar order.
enum DashboardPage: String, CaseIterable, Identifiable {
    case overview, apps, history, battery
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L("概览", "Overview")
        case .apps: return L("应用", "Apps")
        case .history: return L("历史", "History")
        case .battery: return L("电池与充电器", "Battery & Charger")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .apps: return "square.grid.2x2"
        case .history: return "chart.xyaxis.line"
        case .battery: return "bolt.batteryblock"
        }
    }
}

/// Window state shared with the menu bar commands (View ⌘1–4, Quit Process),
/// which live in AppKit outside the SwiftUI tree.
@MainActor
final class DashboardState: ObservableObject {
    static let shared = DashboardState()

    /// Reopens on the last page (Apple: restore what people last viewed).
    @Published var page: DashboardPage {
        didSet { UserDefaults.standard.set(page.rawValue, forKey: "dashboardPage") }
    }
    @Published var selectedApp: AppUsage.ID?
    @Published var range: ChartRange = .hour6
    private init() {
        page = DashboardPage(rawValue: UserDefaults.standard.string(forKey: "dashboardPage") ?? "") ?? .overview
    }
}

/// The main window: a sidebar of pages and a content area in standard
/// grouped forms and a table. Liquid Glass stays in the navigation layer
/// (sidebar, toolbar), where the system draws it; content has none.
struct DashboardView: View {
    @ObservedObject var model: PowerModel
    @ObservedObject var state = DashboardState.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { state.page }, set: { if let p = $0 { state.page = p } })) {
                ForEach(DashboardPage.allCases) { page in
                    Label(page.title, systemImage: page.symbol).tag(page)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detail
                .navigationTitle(state.page.title)
        }
        .frame(minWidth: 820, minHeight: 560)
        .id(settings.language)
    }

    @ViewBuilder private var detail: some View {
        if let s = model.snapshot {
            switch state.page {
            case .overview: OverviewPage(model: model, snapshot: s)
            case .apps: AppsPage(model: model)
            case .history: HistoryPage(model: model)
            case .battery: BatteryPage(snapshot: s)
            }
        } else {
            ContentUnavailableView(L("没有读到电池", "No Battery Found"), systemImage: "battery.0percent",
                                   description: Text(L("Rill 需要带电池的 Mac。", "Rill needs a Mac with a battery.")))
        }
    }
}

// MARK: - Overview

private struct OverviewPage: View {
    @ObservedObject var model: PowerModel
    let snapshot: PowerSnapshot

    var body: some View {
        let s = snapshot
        Form {
            Section {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        BatteryGauge(percent: s.percent, state: s.state)
                            .padding(.bottom, 8)
                        Text("\(s.percent)%")
                            .font(.system(size: 28, weight: .semibold).monospacedDigit())
                        Text(stateText(s))
                            .foregroundStyle(.secondary)
                        if let m = s.minutesToFull {
                            Text(L("\(durationText(m))充满", "Full in \(durationText(m))")).font(.callout).foregroundStyle(.secondary)
                        } else if let m = s.minutesToEmpty {
                            Text(L("剩余 \(durationText(m))", "\(durationText(m)) left")).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 150, alignment: .leading)
                    Divider()
                    FlowView(snapshot: s, height: 160)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 6)
            }

            Section {
                if model.heavyApps.isEmpty {
                    Text(model.energyMeasured ? L("没有应用在大量耗电", "No apps using significant energy")
                                              : L("正在统计，几秒后出现", "Measuring, results in a few seconds"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.heavyApps.prefix(5)) { app in
                        AppSummaryRow(app: app)
                    }
                }
            } header: {
                HStack {
                    Text(L("大量耗电的应用", "Apps Using Significant Energy"))
                    Spacer()
                    Button(L("显示全部", "Show All")) { DashboardState.shared.page = .apps }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            } footer: {
                Text(L("CPU 能耗按应用汇总，近 20 秒平均 1 W 及以上计入。", "CPU energy by app; 1 W or more over 20 seconds counts."))
            }

            TodaySection(minutes: model.minutes)
        }
        .formStyle(.grouped)
    }
}

private struct AppSummaryRow: View {
    let app: AppUsage

    var body: some View {
        let info = AppIdentity.info(for: app)
        LabeledContent {
            Text(app.unresponsive ? L("未响应", "Not Responding") : PowerFormat.watts(app.watts))
                .foregroundStyle(app.unresponsive ? .red : .secondary)
                .monospacedDigit()
        } label: {
            Label {
                Text(info.name)
            } icon: {
                Image(nsImage: info.icon).resizable().frame(width: 18, height: 18)
            }
        }
        .contextMenu { AppContextMenu(app: app) }
    }
}

private struct TodaySection: View {
    let minutes: [MinuteRecord]

    var body: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let e = EnergyStats(records: minutes.filter { $0.t >= start })
        Section(L("今日", "Today")) {
            LabeledContent(L("电脑用电量", "Used by Mac"), value: EnergyStats.format(wh: e.systemWh))
            EnergyRows(stats: e)
        }
        .monospacedDigit()
    }
}

/// Where the Mac's energy came from, then what the battery took in, then
/// power. The two sources add up to the Mac's total; rows that are zero for
/// the period are left out, except the sources.
private struct EnergyRows: View {
    let stats: EnergyStats

    var body: some View {
        LabeledContent(L("来自电池", "From Battery"), value: EnergyStats.format(wh: stats.dischargedWh))
        LabeledContent(L("来自充电器", "From Charger"), value: EnergyStats.format(wh: stats.systemFromChargerWh))
        if stats.chargedWh >= 0.05 {
            LabeledContent(L("充入电池", "Into Battery"), value: EnergyStats.format(wh: stats.chargedWh))
        }
        if let avg = stats.averageSystem {
            LabeledContent(L("平均功率", "Average Power"), value: PowerFormat.watts(avg))
                .help(L("只算 Mac 醒着、有记录的时间", "Counts only time the Mac was awake and recording"))
        }
        if let peak = stats.peakSystem { LabeledContent(L("最高功率（1 分钟均值）", "Peak Power (1-min avg)"), value: PowerFormat.watts(peak)) }
    }
}

// MARK: - History

private struct HistoryPage: View {
    @ObservedObject var model: PowerModel
    @ObservedObject var state = DashboardState.shared

    private var records: [MinuteRecord] {
        let since = Date().addingTimeInterval(-state.range.seconds)
        return Downsample.buckets(model.minutes.filter { $0.t >= since }, maxPoints: 360)
    }

    var body: some View {
        let records = records
        Form {
            EnergySection(minutes: model.minutes.filter { $0.t >= Date().addingTimeInterval(-state.range.seconds) },
                          range: state.range)
            SeriesSection(title: L("电量", "Battery Level"), unit: "%", records: records, color: Palette.charge,
                          domain: 0...100, value: { Double($0.percent) })
            Section(L("功率", "Power")) {
                PowerChart(records: records)
                    .frame(height: 240)
                    .padding(.vertical, 6)
            }
            SeriesSection(title: L("电池温度", "Battery Temperature"), unit: "°C", records: records, color: Palette.discharge,
                          domain: nil, value: { $0.temp })
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker(L("时间范围", "Time Range"), selection: $state.range) {
                    ForEach(ChartRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .help(L("时间范围", "Time Range"))
            }
        }
    }
}

// MARK: - Battery & Charger

private struct BatteryPage: View {
    let snapshot: PowerSnapshot

    var body: some View {
        let s = snapshot
        Form {
            Section(L("电池", "Battery")) {
                LabeledContent(L("电量", "Charge"), value: "\(s.percent)%")
                LabeledContent(L("状态", "Status"), value: stateText(s))
                LabeledContent(L("功率", "Power"),
                               value: (s.batteryWatts >= 0 ? L("充入 ", "In ") : L("放出 ", "Out ")) + PowerFormat.watts(abs(s.batteryWatts)))
                LabeledContent(L("电压与电流", "Voltage & Current"), value: String(format: "%.2f V × %.2f A", s.batteryVolts, s.batteryAmps))
                if let t = s.temperature { LabeledContent(L("温度", "Temperature"), value: String(format: "%.1f °C", t)) }
                if let h = s.health { LabeledContent(L("健康度", "Health"), value: String(format: "%.0f%%", h * 100)) }
                if let full = s.fullChargeCapacity, let design = s.designCapacity {
                    LabeledContent(L("容量", "Capacity"), value: "\(full) / \(design) mAh")
                }
                if let c = s.cycleCount { LabeledContent(L("循环次数", "Cycle Count"), value: "\(c)") }
            }
            Section(L("充电器", "Charger")) {
                // Third-party chargers often report watts and voltages but no
                // name; the connection, not the name, decides this section.
                if s.externalConnected {
                    LabeledContent(L("型号", "Model"), value: s.adapterName ?? L("未提供", "Not reported"))
                    if let w = s.adapterRatedWatts { LabeledContent(L("额定功率", "Rated Power"), value: "\(w) W") }
                    if let v = s.adapterNegotiatedVolts, let a = s.adapterNegotiatedAmps {
                        LabeledContent(L("协商", "Negotiated"), value: String(format: "%.1f V × %.2f A", v, a))
                    }
                    LabeledContent(L("实际输入", "Actual Input"), value: PowerFormat.watts(s.inputWatts))
                    if let rated = s.adapterRatedWatts, rated > 0 {
                        LabeledContent(L("利用率", "Utilization"), value: String(format: "%.0f%%", s.inputWatts / Double(rated) * 100))
                    }
                    LabeledContent(L("转换损耗", "Conversion Loss"), value: PowerFormat.watts(s.lossWatts))
                } else {
                    Text(L("未接充电器", "No charger connected")).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .monospacedDigit()
    }
}

func stateText(_ s: PowerSnapshot) -> String {
    switch s.state {
    case .charging: return L("充电中", "Charging")
    case .full: return L("已充满", "Fully Charged")
    case .paused: return L("暂停充电", "Charging Paused")
    case .onBattery: return L("使用电池", "On Battery")
    case .assisting: return L("充电器不够，电池补电", "Battery assisting the charger")
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
    /// One bar of the energy chart: about a dozen bars per range.
    var slot: TimeInterval {
        switch self {
        case .hour1: return 300
        case .hour6: return 1800
        case .hour24: return 3600
        case .day7: return 86400
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

// MARK: - Charts

/// Energy used over the chosen range. The headline is the number people
/// come for, the Mac's total; hovering a bar swaps it for that bar's value
/// (as Health and Screen Time do), so nothing floats over the bars. Below:
/// where that energy came from, then the power figures behind it. Computed
/// from raw minute records, not the downsampled ones the line charts draw.
private struct EnergySection: View {
    let minutes: [MinuteRecord]
    let range: ChartRange
    @State private var selected: Date?

    var body: some View {
        let slots = EnergyStats.slots(minutes, size: range.slot)
        let total = EnergyStats(records: minutes)
        let hit = selected.flatMap { s in slots.first { s >= $0.start && s < $0.start.addingTimeInterval(range.slot) } }
        Section(L("电脑用电量", "Energy Used by Mac")) {
            if slots.isEmpty {
                Text(L("还没有记录", "No history yet")).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.map { slotLabel($0.start) } ?? L("\(range.label)合计", "Last \(range.label)"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(EnergyStats.format(wh: (hit?.stats ?? total).systemWh))
                        .font(.system(size: 28, weight: .semibold))
                }
                .padding(.top, 4)
                chart(slots, hit: hit).frame(height: 160).padding(.bottom, 6)
                EnergyRows(stats: total)
            }
        }
        .monospacedDigit()
    }

    private func chart(_ slots: [(start: Date, stats: EnergyStats)], hit: (start: Date, stats: EnergyStats)?) -> some View {
        let size = range.slot
        return Chart {
            ForEach(slots, id: \.start) { slot in
                bar(slot, size: size, dimmed: hit != nil && hit?.start != slot.start)
            }
        }
        .chartXScale(domain: (slots.first?.start ?? Date())...(slots.last.map { $0.start.addingTimeInterval(size) } ?? Date()))
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine()
                AxisValueLabel { if let wh = v.as(Double.self) { Text(String(format: wh < 10 ? "%.1f Wh" : "%.0f Wh", wh)) } }
            }
        }
    }

    /// Each bar spans its slot, inset by a tenth on both sides for the gap.
    private func bar(_ slot: (start: Date, stats: EnergyStats), size: TimeInterval, dimmed: Bool) -> some ChartContent {
        let from: Date = slot.start.addingTimeInterval(size * 0.1)
        let to: Date = slot.start.addingTimeInterval(size * 0.9)
        let wh: Double = slot.stats.systemWh
        let color: Color = Palette.system.opacity(dimmed ? 0.35 : 1)
        return RectangleMark(xStart: .value("开始", from), xEnd: .value("结束", to),
                             yStart: .value("Wh", 0.0), yEnd: .value("Wh", wh))
            .foregroundStyle(color)
            .cornerRadius(2)
    }

    private func slotLabel(_ start: Date) -> String {
        let end = start.addingTimeInterval(range.slot)
        if range == .day7 { return start.formatted(.dateTime.month().day().weekday()) }
        return start.formatted(.dateTime.month().day().hour().minute()) + "–" + end.formatted(.dateTime.hour().minute())
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
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value("时间", p.t), y: .value("功率", p.w))
                        .foregroundStyle(by: .value("线", p.series))
                        .lineStyle(by: .value("线", p.series))
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("零", 0)).foregroundStyle(Color.primary.opacity(0.15))
                if let r = nearest {
                    RuleMark(x: .value("选中", r.t))
                        .foregroundStyle(Color.primary.opacity(0.25))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.t, format: .dateTime.month().day().hour().minute())
                                    .foregroundStyle(.secondary)
                                Text(L("输入 ", "Input ") + PowerFormat.watts(r.input))
                                Text(L("电脑 ", "Mac ") + PowerFormat.watts(r.system))
                                Text((r.battery >= 0 ? L("充入 ", "In ") : L("放出 ", "Out ")) + PowerFormat.watts(abs(r.battery)))
                            }
                            .font(.caption.monospacedDigit())
                            .padding(8)
                            .background(.regularMaterial, in: .rect(cornerRadius: 8))
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
                    AxisGridLine()
                    AxisValueLabel { if let w = v.as(Double.self) { Text("\(Int(w)) W") } }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading)
        }
    }
}

private struct SeriesSection: View {
    let title: String
    let unit: String
    let records: [MinuteRecord]
    let color: Color
    let domain: ClosedRange<Double>?
    let value: (MinuteRecord) -> Double?

    var body: some View {
        let pts = records.compactMap { r in value(r).map { (r.t, $0) } }
        Section {
            if pts.count < 2 {
                Text(L("还没有记录", "No history yet")).foregroundStyle(.secondary)
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
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 140)
                .padding(.vertical, 6)
                if let domain {
                    chart.chartYScale(domain: domain)
                } else {
                    chart.chartYScale(domain: .automatic(includesZero: false))
                }
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                if let last = pts.last?.1 {
                    Text(String(format: unit == "%" ? "%.0f %@" : "%.1f %@", last, unit))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
