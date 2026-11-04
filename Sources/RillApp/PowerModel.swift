import Foundation
import RillCore

/// Samples power every two seconds: live watts and temperature from the SMC,
/// percent, adapter and capacity from the battery registry every ten seconds.
/// The panel only gets new values while it is open.
@MainActor
final class PowerModel: ObservableObject {
    @Published private(set) var snapshot: PowerSnapshot?
    @Published private(set) var history = PowerHistory(window: 10 * 60)

    private var latest: PowerSnapshot?
    private var latestHistory = PowerHistory(window: 10 * 60)
    private var registry: PowerSnapshot?
    private var registryDate = Date.distantPast
    private let sensors = LiveSensors()
    private var timer: Timer?
    private var smoothed: LiveReading?

    /// Set by the app delegate while the popover is shown.
    var isVisible = false {
        didSet { if isVisible { publish() } }
    }
    var onUpdate: ((PowerSnapshot?) -> Void)?

    func start(interval: TimeInterval = 2) {
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
        if let s { latestHistory.append(s) }
        if isVisible { publish() }
        onUpdate?(s)
    }

    /// PDTR and PSTR settle at different speeds, so under a changing load the
    /// Mac could briefly read more than the adapter supplies. Averaging the
    /// last two samples (about 4 s) keeps them consistent; over a minute both
    /// agree within 0.1 W (measured 2026-11-04).
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
    }
}
