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
                Text(L("正在大量耗电", "Using Significant Energy"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                ForEach(apps.prefix(3)) { app in
                    let info = AppIdentity.info(for: app)
                    HStack(spacing: 6) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(info.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Text(PowerFormat.watts(app.watts))
                                .font(.system(size: 10.5).monospacedDigit())
                                .foregroundStyle(Color.secondary)
                        }
                        Image(nsImage: info.icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                    }
                    .help(L("\(info.name) 近 20 秒平均 CPU 能耗 \(PowerFormat.watts(app.watts))", "\(info.name): \(PowerFormat.watts(app.watts)) CPU energy, 20-second average"))
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
                Text(L("CPU 能耗，近 20 秒平均；≥ 1 W 记为大量耗电", "CPU energy, 20-second average; 1 W or more counts as significant"))
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
                    HStack(spacing: 10) {
                        Image(nsImage: info.icon).resizable().frame(width: 22, height: 22)
                        Text(info.name)
                            .font(.system(size: 13, weight: isHeavy ? .semibold : .regular))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .frame(width: 180, alignment: .leading)
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isHeavy ? Palette.discharge : Palette.system.opacity(0.55))
                                .frame(width: max(3, g.size.width * CGFloat(min(1, app.watts / peak))), height: 6)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 22)
                        Text(PowerFormat.watts(app.watts))
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(isHeavy ? Color.primary : Color.secondary)
                            .frame(width: 64, alignment: .trailing)
                    }
                }
            }
        }
        .padding(18)
        .glassCard()
    }
}
