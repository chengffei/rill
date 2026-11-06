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

/// The Apps page: every app with measurable activity, in a sortable table
/// like Activity Monitor's. Select a row and use the toolbar button, the
/// context menu or Process ▸ Quit (⌥⌘Q) to quit it.
struct AppsPage: View {
    @ObservedObject var model: PowerModel
    @ObservedObject var state = DashboardState.shared
    @State private var sortOrder = [KeyPathComparator(\AppRow.watts, order: .reverse)]

    struct AppRow: Identifiable {
        let usage: AppUsage
        let name: String
        let icon: NSImage
        var id: String { usage.id }
        var watts: Double { usage.watts }
        var cpu: Double { usage.cpuPercent }
        var memory: UInt64 { usage.memoryBytes }
        /// Hung apps sort above everything when sorting by status.
        var status: Int { usage.unresponsive ? 1 : 0 }
    }

    private var visible: [AppUsage] {
        if state.allProcesses { return model.allApps }
        let dock = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
        return model.allApps.filter { $0.unresponsive || dock.contains($0.responsiblePID) }
    }

    private var rows: [AppRow] {
        visible.map { u in
            let info = AppIdentity.info(for: u)
            return AppRow(usage: u, name: info.name, icon: info.icon)
        }
        .sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            if model.allApps.isEmpty {
                ContentUnavailableView(L("正在统计", "Measuring"), systemImage: "hourglass",
                                       description: Text(L("几秒后出现各应用的用量。", "App usage appears in a few seconds.")))
            } else {
                table
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker(L("显示", "Show"), selection: $state.allProcesses) {
                    Text(L("应用", "Apps")).tag(false)
                    Text(L("所有进程", "All Processes")).tag(true)
                }
                .pickerStyle(.menu)
                .help(L("只看 Dock 里的应用，或所有进程", "Dock apps only, or every process"))
            }
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
        Table(rows, selection: $state.selectedApp, sortOrder: $sortOrder) {
            TableColumn(L("应用", "App"), value: \.name) { row in
                HStack(spacing: 6) {
                    Image(nsImage: row.icon).resizable().frame(width: 16, height: 16)
                    Text(row.name)
                    if row.usage.unresponsive {
                        Text(L("（未响应）", "(Not Responding)")).foregroundStyle(.red)
                    }
                }
            }
            .width(min: 180, ideal: 240)
            TableColumn(L("能耗", "Energy"), value: \.watts) { row in
                Text(PowerFormat.watts(row.watts)).monospacedDigit()
                    .fontWeight(row.watts >= AppEnergyTracker.enterWatts ? .semibold : .regular)
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
            TableColumn(L("最忙的进程", "Busiest Process"), value: \.usage.topName) { row in
                Text(row.usage.topName.isEmpty ? "–" : row.usage.topName)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 160)
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: AppUsage.ID.self) { ids in
            if let id = ids.first, let app = model.allApps.first(where: { $0.id == id }) {
                AppContextMenu(app: app)
            }
        }
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
