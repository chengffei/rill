import Foundation
import IOKit

/// One reading of the battery and adapter, in watts and other display units.
/// Built from the AppleSmartBattery registry entry, which any user can read.
public struct PowerSnapshot: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case charging, full, paused, onBattery, assisting
    }

    public var date: Date
    public var percent: Int
    public var state: State
    public var externalConnected: Bool

    /// Power entering the Mac from the adapter (0 on battery).
    public var inputWatts: Double
    /// Power the Mac itself is using.
    public var systemWatts: Double
    /// Positive while the battery charges, negative while it discharges.
    public var batteryWatts: Double
    /// Heat lost converting adapter power.
    public var lossWatts: Double

    public var batteryVolts: Double
    public var batteryAmps: Double
    public var inputVolts: Double?
    public var inputAmps: Double?

    public var adapterName: String?
    public var adapterRatedWatts: Int?
    public var adapterNegotiatedVolts: Double?
    public var adapterNegotiatedAmps: Double?
    /// USB-C PD levels the charger offers (UsbHvcMenu), lowest voltage first.
    public var adapterProfiles: [AdapterProfile] = []

    public var cycleCount: Int?
    public var designCapacity: Int?
    public var fullChargeCapacity: Int?
    /// Battery temperature in °C, only from the SMC.
    public var temperature: Double?
    /// Minutes, nil while macOS is still estimating.
    public var minutesToFull: Int?
    public var minutesToEmpty: Int?

    public var health: Double? {
        guard let design = designCapacity, let full = fullChargeCapacity, design > 0 else { return nil }
        return Double(full) / Double(design)
    }

    public init(date: Date = Date(), percent: Int, state: State, externalConnected: Bool,
                inputWatts: Double, systemWatts: Double, batteryWatts: Double, lossWatts: Double,
                batteryVolts: Double, batteryAmps: Double, inputVolts: Double? = nil, inputAmps: Double? = nil,
                adapterName: String? = nil, adapterRatedWatts: Int? = nil,
                adapterNegotiatedVolts: Double? = nil, adapterNegotiatedAmps: Double? = nil,
                cycleCount: Int? = nil, designCapacity: Int? = nil, fullChargeCapacity: Int? = nil,
                minutesToFull: Int? = nil, minutesToEmpty: Int? = nil) {
        self.date = date
        self.percent = percent
        self.state = state
        self.externalConnected = externalConnected
        self.inputWatts = inputWatts
        self.systemWatts = systemWatts
        self.batteryWatts = batteryWatts
        self.lossWatts = lossWatts
        self.batteryVolts = batteryVolts
        self.batteryAmps = batteryAmps
        self.inputVolts = inputVolts
        self.inputAmps = inputAmps
        self.adapterName = adapterName
        self.adapterRatedWatts = adapterRatedWatts
        self.adapterNegotiatedVolts = adapterNegotiatedVolts
        self.adapterNegotiatedAmps = adapterNegotiatedAmps
        self.cycleCount = cycleCount
        self.designCapacity = designCapacity
        self.fullChargeCapacity = fullChargeCapacity
        self.minutesToFull = minutesToFull
        self.minutesToEmpty = minutesToEmpty
    }
}

extension PowerSnapshot {
    /// Parses the AppleSmartBattery properties. Units in the registry are
    /// mV, mA and mW; negative currents may arrive as huge unsigned values.
    public init?(registry d: [String: Any], date: Date = Date()) {
        guard let percent = Self.int(d["CurrentCapacity"]) else { return nil }
        let external = Self.bool(d["ExternalConnected"]) ?? false
        let charging = Self.bool(d["IsCharging"]) ?? false
        let full = Self.bool(d["FullyCharged"]) ?? false

        let volts = Double(Self.int(d["Voltage"]) ?? 0) / 1000
        let amps = Double(Self.int(d["InstantAmperage"]) ?? Self.int(d["Amperage"]) ?? 0) / 1000
        let battery = volts * amps

        let telemetry = d["PowerTelemetryData"] as? [String: Any] ?? [:]
        let input = external ? Double(Self.int(telemetry["SystemPowerIn"]) ?? 0) / 1000 : 0
        let loss = external ? Double(Self.int(telemetry["AdapterEfficiencyLoss"]) ?? 0) / 1000 : 0
        // SystemLoad is the Mac's own draw. Without telemetry, it is what
        // comes in minus what goes into the battery.
        let system: Double
        if let load = Self.int(telemetry["SystemLoad"]) {
            system = Double(load) / 1000
        } else {
            system = max(0, input - battery)
        }

        let state: State
        if !external { state = .onBattery }
        else if charging { state = .charging }
        else if full || percent >= 100 { state = .full }
        else { state = .paused }

        let adapter = d["AdapterDetails"] as? [String: Any]
        let battData = d["BatteryData"] as? [String: Any] ?? [:]
        func minutes(_ key: String) -> Int? {
            guard let m = Self.int(d[key]), m > 0, m < 65535 else { return nil }
            return m
        }

        self.init(
            date: date, percent: percent, state: state, externalConnected: external,
            inputWatts: input, systemWatts: system, batteryWatts: battery, lossWatts: loss,
            batteryVolts: volts, batteryAmps: amps,
            inputVolts: Self.int(telemetry["SystemVoltageIn"]).map { Double($0) / 1000 },
            inputAmps: Self.int(telemetry["SystemCurrentIn"]).map { Double($0) / 1000 },
            adapterName: external ? (adapter?["Name"] as? String ?? adapter?["Description"] as? String) : nil,
            adapterRatedWatts: external ? Self.int(adapter?["Watts"]) : nil,
            adapterNegotiatedVolts: external ? Self.int(adapter?["AdapterVoltage"]).map { Double($0) / 1000 } : nil,
            adapterNegotiatedAmps: external ? Self.int(adapter?["Current"]).map { Double($0) / 1000 } : nil,
            cycleCount: Self.int(d["CycleCount"]),
            designCapacity: Self.int(battData["DesignCapacity"]) ?? Self.int(d["DesignCapacity"]),
            fullChargeCapacity: Self.int(battData["FullChargeCapacity"]) ?? Self.int(d["AppleRawMaxCapacity"]),
            minutesToFull: charging ? minutes("AvgTimeToFull") : nil,
            minutesToEmpty: external ? nil : minutes("AvgTimeToEmpty")
        )
        if external, let menu = adapter?["UsbHvcMenu"] as? [[String: Any]] {
            adapterProfiles = menu.compactMap { m in
                guard let v = Self.int(m["MaxVoltage"]), let a = Self.int(m["MaxCurrent"]), v > 0 else { return nil }
                return AdapterProfile(volts: Double(v) / 1000, amps: Double(a) / 1000)
            }
            .sorted { $0.volts < $1.volts }
        }
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let n as NSNumber:
            // Registry stores signed values in 64 bits; a negative current can
            // come back as a value above Int64.max read as UInt64.
            let u = n.uint64Value
            if u > UInt64(Int64.max) { return Int(Int64(bitPattern: u)) }
            return n.intValue
        case let i as Int: return i
        default: return nil
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        default: return nil
        }
    }
}

public enum BatteryReader {
    /// Current AppleSmartBattery properties, or nil on a Mac without a battery.
    public static func read(date: Date = Date()) -> PowerSnapshot? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return PowerSnapshot(registry: dict, date: date)
    }
}

/// One USB-C Power Delivery level a charger offers.
public struct AdapterProfile: Equatable, Sendable {
    public var volts: Double
    public var amps: Double

    public init(volts: Double, amps: Double) {
        self.volts = volts
        self.amps = amps
    }

    /// "5 / 9 / 12 / 15 / 20 V × 3 A" when every level has the same current,
    /// else "5 V × 3 A, 20 V × 2.25 A".
    public static func summary(_ profiles: [AdapterProfile], separator: String = ", ") -> String {
        func n(_ x: Double) -> String { String(format: "%g", x) }
        guard let first = profiles.first else { return "" }
        if profiles.allSatisfy({ $0.amps == first.amps }) {
            return profiles.map { n($0.volts) }.joined(separator: " / ") + " V × \(n(first.amps)) A"
        }
        return profiles.map { "\(n($0.volts)) V × \(n($0.amps)) A" }.joined(separator: separator)
    }
}
