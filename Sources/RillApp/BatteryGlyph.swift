import AppKit

/// Menu bar battery made only of Apple's SF Symbols, as Felix asked
/// (2026-11-04). SF Symbols ship five levels (0, 25, 50, 75, 100 %) and one
/// charging glyph (`battery.100percent.bolt`); they don't support variable
/// values, so the level is rounded to the nearest quarter.
enum BatteryGlyph {
    enum Mark { case none, bolt, plug }

    static func symbolName(percent: Int, mark: Mark) -> String {
        if mark == .bolt { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case 13..<38: return "battery.25percent"
        case 38..<63: return "battery.50percent"
        case 63..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    static func image(percent: Int, mark: Mark) -> NSImage {
        let image = NSImage(systemSymbolName: symbolName(percent: percent, mark: mark), accessibilityDescription: "\(percent)%")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? NSImage()
        image.isTemplate = true
        return image
    }
}
