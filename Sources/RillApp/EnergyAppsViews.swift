import RillCore
import SwiftUI

/// "Using significant energy": apps averaging at least 1 W of CPU energy over
/// about 20 s, with their icons. Mirrors the line in macOS's battery menu.
struct HeavyAppsRow: View {
    let apps: [AppUsage]

    var body: some View {
        HStack(spacing: 10) {
            if apps.isEmpty {
                Text(L("没有应用在大量耗电", "No apps using significant energy"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                Text(apps.contains(where: \.unresponsive) ? L("有应用未响应", "App Not Responding") : L("正在大量耗电", "Using Significant Energy"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                ForEach(apps.prefix(3)) { app in
                    let info = AppIdentity.info(for: app)
                    Button { AppActions.showMenu(for: app) } label: {
                        HStack(spacing: 6) {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(info.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                Text(app.unresponsive ? L("未响应", "Not responding") : PowerFormat.watts(app.watts))
                                    .font(.system(size: 10.5, weight: app.unresponsive ? .semibold : .regular).monospacedDigit())
                                    .foregroundStyle(app.unresponsive ? Color.red : Color.secondary)
                            }
                            Image(nsImage: info.icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("\(info.name)：CPU \(Format.cpu(app.cpuPercent))，近 20 秒平均能耗 \(PowerFormat.watts(app.watts))。点按可退出", "\(info.name): CPU \(Format.cpu(app.cpuPercent)), \(PowerFormat.watts(app.watts)) over 20 s. Click to quit"))
                }
                if apps.count > 3 {
                    Text("+\(apps.count - 3)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
    }
}

/// The Apps page: every app and background service with activity, in one
/// sortable table like Activity Monitor's. Each group opens to its
/// processes, so a terminal's `yes` or a browser's renderer shows under the
/// app it counts toward. Select an app and use the toolbar button, the
/// context menu or Process ▸ Quit (⌥⌘Q) to quit it; a process row offers End.
struct AppsPage: View {
    let model: PowerModel
    @ObservedObject var state = DashboardState.shared
    @State private var sortOrder = [KeyPathComparator(\AppRow.watts, order: .reverse)]
    @State private var search = ""

    struct AppRow: Identifiable {
        let id: String
        let name: String
        let icon: NSImage?
        let watts: Double
        let cpu: Double
        let memory: UInt64
        /// Groups: the busiest process. Processes: empty.
        let busiest: String
        let usage: AppUsage
        /// Set on process rows.
        var process: ProcessUsage?
        var children: [AppRow]?
    }

    static func processRowID(_ pid: pid_t) -> String { "pid:\(pid)" }

    static let systemRowID = "system"

    /// Apps at the top level; macOS's own daemons and agents fold into one
    /// "macOS" row, so the list leads with what you can act on. Dock apps stay
    /// on top even when they live in /System (Finder, Activity Monitor).
    private var rows: [AppRow] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let dock = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
        var top: [AppRow] = []
        var system: [AppRow] = []
        for u in model.allApps {
            guard let row = row(for: u, query: query) else { continue }
            if ProcessGuard.isSystem(path: u.key), !dock.contains(u.responsiblePID), !u.unresponsive {
                system.append(row)
            } else {
                top.append(row)
            }
        }
        if !system.isEmpty, let any = system.first?.usage {
            top.append(AppRow(id: Self.systemRowID, name: L("macOS 系统服务", "macOS Services"),
                              icon: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil),
                              watts: system.reduce(0) { $0 + $1.watts }, cpu: system.reduce(0) { $0 + $1.cpu },
                              memory: system.reduce(0) { $0 + $1.memory },
                              busiest: system.max { $0.cpu + $0.watts < $1.cpu + $1.watts }?.name ?? "",
                              usage: any, children: system.sorted(using: sortOrder)))
        }
        return top.sorted(using: sortOrder)
    }

    private func row(for u: AppUsage, query: String) -> AppRow? {
        let info = AppIdentity.info(for: u)
        let groupMatches = query.isEmpty || info.name.localizedCaseInsensitiveContains(query)
        // A group of one process that is the app itself has nothing to open.
        let showsChildren = u.processes.count > 1 || u.processes.first?.pid != u.responsiblePID
        var kids = showsChildren ? u.processes : []
        if !groupMatches { kids = kids.filter { $0.name.localizedCaseInsensitiveContains(query) } }
        guard groupMatches || !kids.isEmpty else { return nil }
        let children = kids.map { p in
            AppRow(id: Self.processRowID(p.pid), name: p.name, icon: nil, watts: p.watts, cpu: p.cpuPercent,
                   memory: p.memoryBytes, busiest: "", usage: u, process: p)
        }
        return AppRow(id: u.id, name: info.name, icon: info.icon, watts: u.watts, cpu: u.cpuPercent,
                      memory: u.memoryBytes, busiest: u.topName, usage: u,
                      children: children.isEmpty ? nil : children.sorted(using: sortOrder))
    }

    var body: some View {
        Group {
            if model.allApps.isEmpty {
                ContentUnavailableView(L("正在统计", "Measuring"), systemImage: "hourglass",
                                       description: Text(L("几秒后出现各应用的用量。", "App usage appears in a few seconds.")))
            } else {
                VStack(spacing: 0) {
                    SystemLoadBar(model: model)
                    Divider()
                    table
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: L("搜索应用或进程", "Search apps or processes"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let app = selectedUsage { AppActions.confirmQuit(app) }
                } label: {
                    Label(L("退出应用", "Quit App"), systemImage: "xmark.octagon")
                }
                .help(L("退出所选应用", "Quit the selected app"))
                .disabled(selectedUsage.map { !AppActions.canQuit($0) } ?? true)
            }
        }
    }

    private var selectedUsage: AppUsage? {
        guard let id = state.selectedApp else { return nil }
        return model.allApps.first { $0.id == id }
    }

    private var table: some View {
        Table(rows, children: \.children, selection: $state.selectedApp, sortOrder: $sortOrder) {
            TableColumn(L("名称", "Name"), value: \.name) { row in
                HStack(spacing: 6) {
                    if let icon = row.icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(row.name)
                    if let p = row.process {
                        Text("\(p.pid)").monospacedDigit().foregroundStyle(.tertiary)
                    } else if row.usage.unresponsive {
                        Text(L("（未响应）", "(Not Responding)")).foregroundStyle(.red)
                    }
                }
            }
            .width(min: 180, ideal: 260)
            TableColumn(L("能耗", "Energy"), value: \.watts) { row in
                Text(PowerFormat.watts(row.watts)).monospacedDigit()
                    .fontWeight(row.process == nil && row.watts >= AppEnergyTracker.enterWatts ? .semibold : .regular)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)
            TableColumn("CPU", value: \.cpu) { row in
                Text(Format.cpu(row.cpu)).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 70)
            TableColumn(L("内存", "Memory"), value: \.memory) { row in
                Text(row.memory > 0 ? Format.bytes(row.memory) : "–").monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)
            TableColumn(L("最忙的进程", "Busiest Process"), value: \.busiest) { row in
                Text(row.busiest).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 160)
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first { menu(for: id) }
        }
    }

    @ViewBuilder
    private func menu(for id: String) -> some View {
        if let app = model.allApps.first(where: { $0.id == id }) {
            AppContextMenu(app: app)
        } else if let (app, p) = process(id) {
            if ProcessGuard.canTerminate(path: ProcessEnergyReader.path(p.pid), pid: p.pid) {
                Button(L("结束「\(p.name)」…", "End “\(p.name)”…")) { AppActions.endProcess(pid: p.pid, name: p.name) }
            }
            if p.pid != app.responsiblePID, AppActions.canQuit(app) {
                let name = AppIdentity.info(for: app).name
                Button(L("退出 \(name)…", "Quit \(name)…")) { AppActions.confirmQuit(app) }
            }
            Divider()
            Button(L("打开活动监视器", "Open Activity Monitor")) { AppActions.openActivityMonitor() }
        }
    }

    private func process(_ id: String) -> (AppUsage, ProcessUsage)? {
        for app in model.allApps {
            if let p = app.processes.first(where: { Self.processRowID($0.pid) == id }) { return (app, p) }
        }
        return nil
    }
}

/// Whole-machine load above the Apps table, so a slow Mac can be told apart
/// from one busy app: CPU of all cores (with a ~3 min sparkline), load
/// average against the core count, memory used and memory pressure.
/// Reads only `systemLoad` and `cpuHistory`, so the table does not redraw for it.
struct SystemLoadBar: View {
    let model: PowerModel

    var body: some View {
        let load = model.systemLoad
        HStack(alignment: .top, spacing: 0) {
            metric(L("CPU", "CPU"),
                   value: load?.cpuTotal.map { String(format: "%.0f%%", $0) } ?? "–",
                   detail: cpuDetail(load),
                   tint: (load?.cpuTotal ?? 0) >= 80 ? .orange : nil) {
                Sparkline(values: model.cpuHistory)
                    .frame(width: 72, height: 22)
            }
            .help(cpuHelp(load))
            separator
            metric(L("负载", "Load"),
                   value: load.flatMap { $0.loadAverage.first }.map { String(format: "%.2f", $0) } ?? "–",
                   detail: loadDetail(load),
                   tint: overloaded(load) ? .orange : nil) { EmptyView() }
                .help(L("近 1 分钟平均有多少个线程在跑或在排队。长期高于核心数说明 CPU 不够用。",
                        "Threads running or waiting, averaged over 1 minute. Staying above the core count means the CPU is saturated."))
            separator
            metric(L("内存", "Memory"),
                   value: load.map { Format.bytes($0.memoryUsed) } ?? "–",
                   detail: load.map { L("共 \(Format.bytes($0.memoryTotal))，压缩 \(Format.bytes($0.memoryCompressed))",
                                         "of \(Format.bytes($0.memoryTotal)), \(Format.bytes($0.memoryCompressed)) compressed") } ?? " ",
                   tint: nil) { EmptyView() }
                .help(L("与活动监视器的「已使用内存」同一口径：应用内存、联动内存、被压缩内存之和。",
                        "Same as Activity Monitor's Memory Used: app, wired and compressed memory."))
            separator
            metric(L("内存压力", "Memory Pressure"),
                   value: load.map { pressureName($0.pressure) } ?? "–",
                   detail: load.map { L("交换 \(Format.bytes($0.swapUsed))", "Swap \(Format.bytes($0.swapUsed))") } ?? " ",
                   tint: load.map { pressureTint($0.pressure) } ?? nil) { EmptyView() }
                .help(L("黄色或红色表示内存不够，系统在压缩和换页，会变卡。",
                        "Yellow or red means memory is short and macOS is compressing and swapping, which slows things down."))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var separator: some View {
        Divider().frame(height: 36).padding(.horizontal, 14)
    }

    private func metric<Accessory: View>(_ title: String, value: String, detail: String, tint: Color?,
                                         @ViewBuilder accessory: () -> Accessory) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 8) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint ?? .primary)
                accessory()
            }
            Text(detail).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cpuDetail(_ load: SystemLoad?) -> String {
        guard let load, let u = load.cpuUser, let s = load.cpuSystem else { return " " }
        return L(String(format: "用户 %.0f%%，系统 %.0f%%", u, s),
                 String(format: "User %.0f%%, system %.0f%%", u, s))
    }

    private func cpuHelp(_ load: SystemLoad?) -> String {
        let busy = load?.busyCores.map { String(format: "%.1f", $0) } ?? "–"
        return L("全部核心合计，100% 是所有核心满载，现在约等于 \(busy) 个核心满载。表格里的 CPU 按单核算，100% 是一个核心。曲线是近 3 分钟。",
                 "Share of all cores; 100% is every core busy. Now about \(busy) cores' worth. The table's CPU column counts one core as 100%. The line covers the last 3 minutes.")
    }

    private func loadDetail(_ load: SystemLoad?) -> String {
        guard let load, load.loadAverage.count == 3 else { return " " }
        let a = load.loadAverage
        return L(String(format: "5 分 %.2f，15 分 %.2f，%d 核", a[1], a[2], load.cores),
                 String(format: "5 min %.2f, 15 min %.2f, %d cores", a[1], a[2], load.cores))
    }

    private func overloaded(_ load: SystemLoad?) -> Bool {
        guard let load, let one = load.loadAverage.first else { return false }
        return one > Double(load.cores)
    }

    private func pressureName(_ p: MemoryPressure) -> String {
        switch p {
        case .normal: return L("正常", "Normal")
        case .warning: return L("偏高", "Elevated")
        case .critical: return L("严重", "Critical")
        }
    }

    private func pressureTint(_ p: MemoryPressure) -> Color? {
        switch p {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

/// A plain line over a fixed 0–100 % scale; one Path, no Charts, so a redraw
/// every 4 s stays cheap.
private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            let n = PowerModel.cpuHistoryLength
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(n - 1)
            let x0 = size.width - step * CGFloat(values.count - 1)
            var line = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: x0 + step * CGFloat(i), y: size.height * (1 - CGFloat(min(max(v, 0), 100)) / 100))
                i == 0 ? line.move(to: p) : line.addLine(to: p)
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: x0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(.accentColor.opacity(0.15)))
            ctx.stroke(line, with: .color(.accentColor), lineWidth: 1.2)
        }
        .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.04)))
        .accessibilityHidden(true)
    }
}

/// The same actions as the panel's click menu, as SwiftUI menu items.
struct AppContextMenu: View {
    let app: AppUsage

    var body: some View {
        let info = AppIdentity.info(for: app)
        if AppActions.canQuit(app) {
            Button(L("退出 \(info.name)…", "Quit \(info.name)…")) { AppActions.confirmQuit(app) }
        }
        if let top = AppActions.busiestOtherProcess(app) {
            Button(L("结束「\(top.name)」…", "End “\(top.name)”…")) { AppActions.endProcess(pid: top.pid, name: top.name) }
        }
        Divider()
        Button(L("打开活动监视器", "Open Activity Monitor")) { AppActions.openActivityMonitor() }
    }
}
