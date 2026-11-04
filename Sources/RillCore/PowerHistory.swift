import Foundation

/// The most recent readings, oldest first, kept for a fixed time window.
public struct PowerHistory: Sendable {
    public private(set) var samples: [PowerSnapshot] = []
    public let window: TimeInterval

    public init(window: TimeInterval) {
        self.window = window
    }

    public mutating func append(_ snapshot: PowerSnapshot) {
        samples.append(snapshot)
        let cutoff = snapshot.date.addingTimeInterval(-window)
        if let firstKept = samples.firstIndex(where: { $0.date >= cutoff }), firstKept > 0 {
            samples.removeFirst(firstKept)
        }
    }

    /// Mean system draw over the window, nil when empty.
    public var averageSystemWatts: Double? {
        guard !samples.isEmpty else { return nil }
        return samples.map(\.systemWatts).reduce(0, +) / Double(samples.count)
    }

    public var peakSystemWatts: Double? {
        samples.map(\.systemWatts).max()
    }
}

public enum PowerFormat {
    /// "17.6 W"; one decimal below 100 W.
    public static func watts(_ value: Double) -> String {
        let v = abs(value)
        return v >= 100 ? String(format: "%.0f W", v) : String(format: "%.1f W", v)
    }

    /// "1 小时 25 分", "25 分".
    public static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h) 小时 \(m) 分" : "\(m) 分"
    }
}
