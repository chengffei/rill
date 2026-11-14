import Foundation

/// One minute of readings averaged, the unit Rill keeps on disk.
public struct MinuteRecord: Codable, Equatable, Sendable {
    /// Start of the minute.
    public var t: Date
    public var input: Double
    public var system: Double
    /// Positive while charging.
    public var battery: Double
    public var temp: Double?
    public var percent: Int
    /// Seconds of the minute the samples cover, used to weight energy.
    public var seconds: Double

    public init(t: Date, input: Double, system: Double, battery: Double, temp: Double?, percent: Int, seconds: Double) {
        self.t = t
        self.input = input
        self.system = system
        self.battery = battery
        self.temp = temp
        self.percent = percent
        self.seconds = seconds
    }
}

/// Folds two-second snapshots into minute averages.
public struct MinuteAggregator: Sendable {
    private var minute: Date?
    private var count = 0
    private var input = 0.0, system = 0.0, battery = 0.0, temp = 0.0, tempCount = 0
    private var percent = 0
    private var first: Date?, last: Date?
    public let interval: TimeInterval

    public init(interval: TimeInterval = 2) {
        self.interval = interval
    }

    /// Adds a sample; returns the finished previous minute when this sample
    /// starts a new one.
    public mutating func add(_ s: PowerSnapshot) -> MinuteRecord? {
        let m = Self.minuteStart(s.date)
        var finished: MinuteRecord?
        if let current = minute, current != m {
            finished = record()
            reset()
        }
        minute = m
        count += 1
        input += s.inputWatts
        system += s.systemWatts
        battery += s.batteryWatts
        if let t = s.temperature { temp += t; tempCount += 1 }
        percent = s.percent
        if first == nil { first = s.date }
        last = s.date
        return finished
    }

    /// The minute in progress, for showing up-to-date totals.
    public func partial() -> MinuteRecord? { record() }

    private func record() -> MinuteRecord? {
        guard let minute, count > 0, let first, let last else { return nil }
        let n = Double(count)
        // Each sample stands for one interval; never more than the minute.
        let covered = min(60, max(last.timeIntervalSince(first) + interval, interval))
        return MinuteRecord(t: minute, input: input / n, system: system / n, battery: battery / n,
                            temp: tempCount > 0 ? temp / Double(tempCount) : nil, percent: percent, seconds: covered)
    }

    private mutating func reset() {
        count = 0; input = 0; system = 0; battery = 0; temp = 0; tempCount = 0; first = nil; last = nil
    }

    static func minuteStart(_ d: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (d.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }
}

public struct EnergyStats: Equatable, Sendable {
    public var inputWh = 0.0
    public var systemWh = 0.0
    public var chargedWh = 0.0
    public var dischargedWh = 0.0
    public var averageSystem: Double?
    public var peakSystem: Double?

    public init(records: [MinuteRecord]) {
        var weighted = 0.0, seconds = 0.0
        for r in records {
            let h = r.seconds / 3600
            inputWh += r.input * h
            systemWh += r.system * h
            if r.battery > 0 { chargedWh += r.battery * h } else { dischargedWh += -r.battery * h }
            weighted += r.system * r.seconds
            seconds += r.seconds
        }
        averageSystem = seconds > 0 ? weighted / seconds : nil
        peakSystem = records.map(\.system).max()
    }
}

public extension EnergyStats {
    /// Energy per time slot for a bar chart: slots of `size` seconds aligned to
    /// local midnight (5 min, 30 min, 1 h), or calendar days when `size` is a
    /// day or more. Only slots with records are returned, oldest first.
    static func slots(_ records: [MinuteRecord], size: TimeInterval,
                      calendar: Calendar = .current) -> [(start: Date, stats: EnergyStats)] {
        var groups: [Date: [MinuteRecord]] = [:]
        for r in records {
            let day = calendar.startOfDay(for: r.t)
            let key = size >= 86400 ? day
                : day.addingTimeInterval((r.t.timeIntervalSince(day) / size).rounded(.down) * size)
            groups[key, default: []].append(r)
        }
        return groups.keys.sorted().map { ($0, EnergyStats(records: groups[$0]!)) }
    }

    /// "8.4 Wh", "126 Wh", "1.35 kWh".
    static func format(wh: Double) -> String {
        if wh >= 1000 { return String(format: "%.2f kWh", wh / 1000) }
        return wh >= 100 ? String(format: "%.0f Wh", wh) : String(format: "%.1f Wh", wh)
    }
}

public enum Downsample {
    /// Averages records into buckets so a chart never draws more than about
    /// `maxPoints` points per series.
    public static func buckets(_ records: [MinuteRecord], maxPoints: Int) -> [MinuteRecord] {
        guard records.count > maxPoints, let first = records.first, let last = records.last else { return records }
        let span = last.t.timeIntervalSince(first.t) + 60
        let size = max(60, (span / Double(maxPoints) / 60).rounded(.up) * 60)
        var out: [MinuteRecord] = []
        var group: [MinuteRecord] = []
        var start = first.t
        func flush() {
            guard !group.isEmpty else { return }
            let n = Double(group.count)
            let temps = group.compactMap(\.temp)
            out.append(MinuteRecord(t: start, input: group.map(\.input).reduce(0, +) / n,
                                    system: group.map(\.system).reduce(0, +) / n,
                                    battery: group.map(\.battery).reduce(0, +) / n,
                                    temp: temps.isEmpty ? nil : temps.reduce(0, +) / Double(temps.count),
                                    percent: group.last!.percent, seconds: group.map(\.seconds).reduce(0, +)))
            group = []
        }
        for r in records {
            if r.t.timeIntervalSince(start) >= size {
                flush()
                start = r.t
            }
            group.append(r)
        }
        flush()
        return out
    }
}
