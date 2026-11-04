import Foundation

/// Live power readings from the SMC. The battery registry entry only refreshes
/// about once a minute; these keys change every second.
public struct LiveReading: Equatable, Sendable {
    /// PDTR: power in from the adapter, watts.
    public var inputWatts: Double
    /// PSTR: power the whole Mac draws, watts.
    public var systemWatts: Double
    /// B0AV / B0AC: battery voltage and current, positive while charging.
    public var batteryVolts: Double
    public var batteryAmps: Double
    /// TB0T: battery temperature, °C.
    public var temperature: Double?

    public init(inputWatts: Double, systemWatts: Double, batteryVolts: Double, batteryAmps: Double, temperature: Double?) {
        self.inputWatts = inputWatts
        self.systemWatts = systemWatts
        self.batteryVolts = batteryVolts
        self.batteryAmps = batteryAmps
        self.temperature = temperature
    }
}

public final class LiveSensors {
    private let smc: SMC

    public init?() {
        guard let smc = SMC(), smc.double("PSTR") != nil, smc.double("B0AV") != nil else { return nil }
        self.smc = smc
    }

    public func read() -> LiveReading? {
        guard let system = smc.double("PSTR"), let mv = smc.double("B0AV"), let ma = smc.double("B0AC") else { return nil }
        return LiveReading(
            inputWatts: max(0, smc.double("PDTR") ?? 0),
            systemWatts: max(0, system),
            batteryVolts: mv / 1000,
            batteryAmps: ma / 1000,
            temperature: smc.double("TB0T")
        )
    }
}

extension PowerSnapshot {
    /// This snapshot with live power and a state worked out from it. Percent,
    /// adapter and capacity stay from the registry; they change slowly.
    public func merging(_ live: LiveReading, date: Date = Date()) -> PowerSnapshot {
        var s = self
        s.date = date
        // Live input decides: the registry lags plugging and unplugging by up to a minute.
        s.externalConnected = live.inputWatts > 0.5
        s.inputWatts = s.externalConnected ? live.inputWatts : 0
        s.systemWatts = live.systemWatts
        s.batteryVolts = live.batteryVolts
        s.batteryAmps = live.batteryAmps
        s.batteryWatts = live.batteryVolts * live.batteryAmps
        s.lossWatts = s.externalConnected ? max(0, s.inputWatts - s.systemWatts - max(0, s.batteryWatts)) : 0
        s.temperature = live.temperature
        if !s.externalConnected {
            s.state = .onBattery
        } else if s.batteryWatts > 0.3 {
            s.state = .charging
        } else if s.batteryWatts < -0.3 {
            // Plugged in but the adapter can't keep up.
            s.state = .assisting
        } else {
            s.state = percent >= 100 || state == .full ? .full : .paused
        }
        return s
    }
}
