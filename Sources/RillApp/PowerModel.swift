import Foundation
import Observation
import RillCore

/// Samples power every two seconds: live watts and temperature from the SMC,
/// percent, adapter and capacity from the battery registry every ten seconds.
///
/// Views see new values only while the panel or the Dashboard is showing.
/// Their SwiftUI trees live on in the closed popover and window, and a
/// change published to them re-ran layout every two seconds: 2.4 % of a core
/// hidden, against 0.65 % with nothing ever opened (2026-11-22). Per-app
/// energy is read every 4 s while something shows it and every 20 s otherwise.
@Observable @MainActor
final class PowerModel {
    private(set) var snapshot: PowerSnapshot?
    private(set) var history = PowerHistory(window: 10 * 60)
    /// Completed minute records for the last 7 days; changes once a minute.
    private(set) var minutes: [MinuteRecord] = []
    /// The minute in progress, for live totals.
    private(set) var partialMinute: MinuteRecord?
    /// Apps using significant energy (hung ones first).
    private(set) var heavyApps: [AppUsage] = []
    /// Every app with measurable activity, for the Apps table.
    private(set) var allApps: [AppUsage] = []
    /// False until the first two energy readings give a rate.
    private(set) var energyMeasured = false

    @ObservationIgnored private let energyReader = ProcessEnergyReader()
    @ObservationIgnored private var energyTracker = AppEnergyTracker(timeConstant: 20)
    @ObservationIgnored private let hangDetector = HangDetector()
    /// Responsible pid and bundle path of apps the window server reports hung.
    @ObservationIgnored private var hung: [(pid: pid_t, key: String?)] = []
    @ObservationIgnored private var lastEnergyRead = Date.distantPast
    /// The app lists need rebuilding from the tracker before the next publish.
    @ObservationIgnored private var appsDirty = false

    @ObservationIgnored private let store = HistoryStore(directory: ProcessInfo.processInfo.environment["RILL_HISTORY_DIR"].map { URL(fileURLWithPath: $0) })
    @ObservationIgnored private var aggregator = MinuteAggregator(interval: 2)
    @ObservationIgnored private var savedMinutes: [MinuteRecord] = []
    @ObservationIgnored private var minutesDirty = false

    @ObservationIgnored private var latest: PowerSnapshot?
    @ObservationIgnored private var latestHistory = PowerHistory(window: 10 * 60)
    @ObservationIgnored private var registry: PowerSnapshot?
    @ObservationIgnored private var registryDate = Date.distantPast
    @ObservationIgnored private let sensors = LiveSensors()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var smoothed: LiveReading?

    /// Set by the app delegate while the popover or the Dashboard is on screen.
    @ObservationIgnored var popoverVisible = false { didSet { visibilityChanged() } }
    @ObservationIgnored var dashboardVisible = false { didSet { visibilityChanged() } }
    var isVisible: Bool { popoverVisible || dashboardVisible }
    /// Called after every sample with the latest reading, shown or not.
    @ObservationIgnored var onUpdate: ((PowerSnapshot?) -> Void)?

    /// Seconds between per-app energy readings while something shows them, and while nothing does.
    static let energyIntervalShown: TimeInterval = 4
    static let energyIntervalHidden: TimeInterval = 20

    func start(interval: TimeInterval = 2) {
        store.prune()
        savedMinutes = store.load(since: Date().addingTimeInterval(-7 * 86400))
        minutes = savedMinutes
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
        // The timer fires with up to 0.5 s of slack, so the interval is
        // checked with a little margin.
        let energyInterval = isVisible ? Self.energyIntervalShown : Self.energyIntervalHidden
        if now.timeIntervalSince(lastEnergyRead) >= energyInterval - 1 {
            readEnergy(at: now)
        }
        if let s {
            latestHistory.append(s)
            if let done = aggregator.add(s) {
                store.append(done)
                savedMinutes.append(done)
                let cutoff = now.addingTimeInterval(-7 * 86400)
                if let first = savedMinutes.first, first.t < cutoff {
                    savedMinutes.removeAll { $0.t < cutoff }
                }
                minutesDirty = true
            }
        }
        if isVisible { publish() }
        onUpdate?(s)
    }

    /// Reading ~550 processes costs about a millisecond.
    private func readEnergy(at now: Date) {
        lastEnergyRead = now
        energyTracker.ingest(energyReader.read(), at: now)
        hung = hangDetector.check().map { ($0.processIdentifier, $0.bundleURL?.path) }
        appsDirty = true
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

    /// On opening, the views get everything current at once; the energy
    /// reading is refreshed too when the slower hidden cadence left it stale.
    private func visibilityChanged() {
        guard isVisible else { return }
        let now = Date()
        if now.timeIntervalSince(lastEnergyRead) >= Self.energyIntervalShown - 1 {
            readEnergy(at: now)
        }
        appsDirty = true
        publish()
    }

    private func publish() {
        snapshot = latest
        history = latestHistory
        partialMinute = aggregator.partial()
        if minutesDirty {
            minutes = savedMinutes
            minutesDirty = false
        }
        if appsDirty {
            refreshApps()
            appsDirty = false
        }
    }

    /// Rebuilds the app lists from the tracker, once per energy reading.
    private func refreshApps() {
        let all = energyTracker.usages().map(markHung)
        let stuck = hungUsages(from: all)
        let stuckKeys = Set(stuck.map(\.key))
        // Hung apps first: they need attention even at 0 W.
        let heavy = stuck + all.filter { energyTracker.isHeavy($0.key) && !stuckKeys.contains($0.key) }
        if heavy != heavyApps { heavyApps = heavy }
        if !energyMeasured, !all.isEmpty { energyMeasured = true }
        if dashboardVisible {
            let everything = stuck + all.filter { !stuckKeys.contains($0.key) }
            if everything != allApps { allApps = everything }
        }
    }

    private func markHung(_ u: AppUsage) -> AppUsage {
        var u = u
        u.unresponsive = hung.contains { $0.pid == u.responsiblePID || $0.key == u.key }
        return u
    }

    /// One entry per hung app, taken from the tracker when it has one.
    private func hungUsages(from all: [AppUsage]) -> [AppUsage] {
        hung.map { h in
            if let u = all.first(where: { $0.unresponsive && ($0.responsiblePID == h.pid || $0.key == h.key) }) { return u }
            var u = AppUsage(key: h.key ?? "pid \(h.pid)", responsiblePID: h.pid, watts: 0)
            u.unresponsive = true
            return u
        }
    }
}
