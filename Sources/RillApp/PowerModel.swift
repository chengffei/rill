import Foundation
import RillCore

/// Samples power every two seconds: live watts and temperature from the SMC,
/// percent, adapter and capacity from the battery registry every ten seconds.
/// The panel only gets new values while it is open.
@MainActor
final class PowerModel: ObservableObject {
    @Published private(set) var snapshot: PowerSnapshot?
    @Published private(set) var history = PowerHistory(window: 10 * 60)
    /// Minute records for the last 7 days plus the minute in progress.
    @Published private(set) var minutes: [MinuteRecord] = []
    /// Apps using significant energy, and the busiest apps overall.
    @Published private(set) var heavyApps: [AppUsage] = []
    @Published private(set) var topApps: [AppUsage] = []

    private let energyReader = ProcessEnergyReader()
    private var energyTracker = AppEnergyTracker(timeConstant: 20)
    private var tick = 0

    private let store = HistoryStore(directory: ProcessInfo.processInfo.environment["RILL_HISTORY_DIR"].map { URL(fileURLWithPath: $0) })
    private var aggregator = MinuteAggregator(interval: 2)
    private var savedMinutes: [MinuteRecord] = []

    private var latest: PowerSnapshot?
    private var latestHistory = PowerHistory(window: 10 * 60)
    private var registry: PowerSnapshot?
    private var registryDate = Date.distantPast
    private let sensors = LiveSensors()
    private var timer: Timer?
    private var smoothed: LiveReading?

    /// Set by the app delegate while the popover or the Dashboard is shown.
    var popoverVisible = false { didSet { if isVisible { publish() } } }
    var dashboardVisible = false { didSet { if isVisible { publish() } } }
    var isVisible: Bool { popoverVisible || dashboardVisible }
    var onUpdate: ((PowerSnapshot?) -> Void)?

    func start(interval: TimeInterval = 2) {
        store.prune()
        savedMinutes = store.load(since: Date().addingTimeInterval(-7 * 86400))
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer?.tolerance = 0.5
    }

    private func sample() {
        let now = Date()
        if registry == nil || now.timeIntervalSince(registryDate) >= 10 {
            registry = BatteryReader.read(date: now)
            registryDate = now
        }
        var s = registry
        if let base = s, let raw = sensors?.read() {
            let live = smooth(raw)
            s = base.merging(live, date: now)
        } else {
            s?.date = now
        }
        latest = s
        // Per-app energy every other sample (4 s); reading ~800 processes
        // costs about a millisecond.
        tick += 1
        if tick % 2 == 1 {
            energyTracker.ingest(energyReader.read(), at: now)
        }
        // The panel's size depends on the snapshot (adapter rows come and go),
        // so keep it current even while closed; the popover is sized from it
        // before it opens. Only the heavier history waits for visibility.
        if snapshot != s { snapshot = s }
        if let s {
            latestHistory.append(s)
            if let done = aggregator.add(s) {
                store.append(done)
                savedMinutes.append(done)
                let cutoff = now.addingTimeInterval(-7 * 86400)
                if let first = savedMinutes.first, first.t < cutoff {
                    savedMinutes.removeAll { $0.t < cutoff }
                }
            }
        }
        if isVisible { publish() }
        onUpdate?(s)
    }

    /// Averages the last two samples (about 4 s) to steady the readings.
    /// The Mac's draw is derived from input and battery in `merging`, so the
    /// flow always adds up.
    private func smooth(_ r: LiveReading) -> LiveReading {
        guard let p = smoothed else { smoothed = r; return r }
        // Plugging or unplugging is a step, not noise.
        if (p.inputWatts > 0.5) != (r.inputWatts > 0.5) { smoothed = r; return r }
        var m = r
        m.inputWatts = (p.inputWatts + r.inputWatts) / 2
        m.systemWatts = (p.systemWatts + r.systemWatts) / 2
        m.batteryAmps = (p.batteryAmps + r.batteryAmps) / 2
        smoothed = r
        return m
    }

    private func publish() {
        snapshot = latest
        history = latestHistory
        let heavy = energyTracker.heavyApps()
        if heavy != heavyApps { heavyApps = heavy }
        let top = Array(energyTracker.usages().prefix(5))
        if dashboardVisible, top != topApps { topApps = top }
        if dashboardVisible {
            minutes = savedMinutes + (aggregator.partial().map { [$0] } ?? [])
        }
    }
}
