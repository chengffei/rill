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

/// Dashboard card: the busiest apps right now, heavy ones marked.
struct EnergyAppsCard: View {
    let top: [AppUsage]
    let heavy: [AppUsage]
    let measured: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("耗电应用", "Energy by App")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary)
                Spacer()
                Text(L("CPU 能耗，近 20 秒平均；≥ 1 W 记为大量耗电；点按应用可退出", "CPU energy, 20-second average; 1 W or more counts as significant; click an app to quit it"))
                    .font(.system(size: 11)).foregroundStyle(Color.secondary)
            }
            if top.isEmpty {
                Text(measured ? L("没有应用在明显耗电（都低于 0.05 W）", "No app is drawing noticeable power (all under 0.05 W)") : L("正在统计，几秒后出现", "Measuring, results in a few seconds"))
                    .font(.system(size: 13)).foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                let peak = max(top.first?.watts ?? 1, AppEnergyTracker.enterWatts)
                ForEach(top) { app in
                    let info = AppIdentity.info(for: app)
                    let isHeavy = heavy.contains { $0.key == app.key }
                    Button { AppActions.showMenu(for: app) } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: info.icon).resizable().frame(width: 22, height: 22)
                        HStack(spacing: 6) {
                            Text(info.name)
                                .font(.system(size: 13, weight: isHeavy ? .semibold : .regular))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            if app.unresponsive {
                                Text(L("未响应", "Not responding"))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.red))
                                    .fixedSize()
                            }
                        }
                        .frame(width: 210, alignment: .leading)
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isHeavy ? Palette.discharge : Palette.system.opacity(0.55))
                                .frame(width: max(3, g.size.width * CGFloat(min(1, app.watts / peak))), height: 6)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 22)
                        Text("CPU " + Format.cpu(app.cpuPercent))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(Color.secondary)
                            .frame(width: 76, alignment: .trailing)
                        Text(app.memoryBytes > 0 ? Format.bytes(app.memoryBytes) : "–")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(Color.secondary)
                            .frame(width: 64, alignment: .trailing)
                        Text(PowerFormat.watts(app.watts))
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(isHeavy ? Color.primary : Color.secondary)
                            .frame(width: 64, alignment: .trailing)
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondary)
                    }
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .glassCard()
    }
}
