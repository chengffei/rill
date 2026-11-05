import RillCore
import SwiftUI

/// A battery drawn at the exact charge level, for the Dashboard's status
/// area. Static: no animation, which inside glass would cost CPU every frame.
struct BatteryGauge: View {
    let percent: Int
    let state: PowerSnapshot.State

    var body: some View {
        let level = CGFloat(max(0, min(100, percent))) / 100
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5)
                GeometryReader { g in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(fill)
                        .frame(width: max(4, (g.size.width - 8) * level))
                        .padding(4)
                }
                if state == .charging || state == .full || state == .paused || state == .assisting {
                    Image(systemName: state == .charging ? "bolt.fill" : "powerplug.portrait.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1)
                        .frame(maxWidth: .infinity)
                }
            }
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.primary.opacity(0.35))
                .frame(width: 3.5, height: 10)
        }
        .frame(width: 66, height: 30)
        .accessibilityLabel(L("电量 \(percent)%", "Battery \(percent)%"))
    }

    private var fill: Color {
        if percent <= 20, state == .onBattery { return .red }
        return state == .onBattery ? Color.primary.opacity(0.75) : Palette.charge
    }
}
