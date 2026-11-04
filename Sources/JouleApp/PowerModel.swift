import Foundation
import JouleCore

/// Samples the battery on a timer and keeps the last ten minutes.
@MainActor
final class PowerModel: ObservableObject {
    @Published private(set) var snapshot: PowerSnapshot?
    @Published private(set) var history = PowerHistory(window: 10 * 60)

    private var timer: Timer?
    var onUpdate: ((PowerSnapshot?) -> Void)?

    func start(interval: TimeInterval = 2) {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer?.tolerance = 0.5
    }

    private func sample() {
        let s = BatteryReader.read()
        snapshot = s
        if let s { history.append(s) }
        onUpdate?(s)
    }
}
