import XCTest
@testable import RillCore

final class PowerSnapshotTests: XCTestCase {
    /// Values from a real M1 Pro on a 67 W adapter, fully charged (2026-11-04).
    private var pluggedFull: [String: Any] {
        [
            "CurrentCapacity": 100, "ExternalConnected": true, "IsCharging": false, "FullyCharged": true,
            "Voltage": 12757, "Amperage": 0, "InstantAmperage": 0, "CycleCount": 304,
            "AvgTimeToFull": 65535, "AvgTimeToEmpty": 65535,
            "PowerTelemetryData": ["SystemPowerIn": 17625, "SystemLoad": 17625, "AdapterEfficiencyLoss": 328,
                                   "SystemVoltageIn": 20243, "SystemCurrentIn": 871],
            "AdapterDetails": ["Name": "67W USB-C Power Adapter", "Watts": 65, "AdapterVoltage": 20000, "Current": 3260],
            "BatteryData": ["DesignCapacity": 6075, "FullChargeCapacity": 5352],
        ]
    }

    func testPluggedInFullBattery() throws {
        let s = try XCTUnwrap(PowerSnapshot(registry: pluggedFull))
        XCTAssertEqual(s.state, .full)
        XCTAssertEqual(s.inputWatts, 17.625, accuracy: 0.001)
        XCTAssertEqual(s.systemWatts, 17.625, accuracy: 0.001)
        XCTAssertEqual(s.batteryWatts, 0)
        XCTAssertEqual(s.lossWatts, 0.328, accuracy: 0.001)
        XCTAssertEqual(s.adapterRatedWatts, 65)
        XCTAssertEqual(s.adapterNegotiatedVolts, 20)
        XCTAssertEqual(try XCTUnwrap(s.health), 5352.0 / 6075.0, accuracy: 0.0001)
        XCTAssertNil(s.minutesToFull)
        XCTAssertNil(s.minutesToEmpty)
    }

    func testChargingSplitsInputBetweenSystemAndBattery() throws {
        var d = pluggedFull
        d["IsCharging"] = true
        d["FullyCharged"] = false
        d["CurrentCapacity"] = 62
        d["InstantAmperage"] = 2400
        d["Voltage"] = 12500
        d["AvgTimeToFull"] = 85
        d["PowerTelemetryData"] = ["SystemPowerIn": 45000, "SystemLoad": 15000, "AdapterEfficiencyLoss": 1200]
        let s = try XCTUnwrap(PowerSnapshot(registry: d))
        XCTAssertEqual(s.state, .charging)
        XCTAssertEqual(s.batteryWatts, 30, accuracy: 0.001)
        XCTAssertEqual(s.systemWatts, 15, accuracy: 0.001)
        XCTAssertEqual(s.minutesToFull, 85)
    }

    /// Discharge current is negative; the registry may hand it back as an
    /// unsigned 64-bit value.
    func testOnBatteryReadsNegativeCurrent() throws {
        var d = pluggedFull
        d["ExternalConnected"] = false
        d["FullyCharged"] = false
        d["CurrentCapacity"] = 80
        d["InstantAmperage"] = NSNumber(value: UInt64(bitPattern: -1000))
        d["Voltage"] = 12000
        d["AvgTimeToEmpty"] = 300
        d["PowerTelemetryData"] = ["SystemPowerIn": 0, "SystemLoad": 12000]
        let s = try XCTUnwrap(PowerSnapshot(registry: d))
        XCTAssertEqual(s.state, .onBattery)
        XCTAssertEqual(s.batteryWatts, -12, accuracy: 0.001)
        XCTAssertEqual(s.inputWatts, 0)
        XCTAssertNil(s.adapterName)
        XCTAssertEqual(s.minutesToEmpty, 300)
    }

    func testPausedBelowFull() throws {
        var d = pluggedFull
        d["FullyCharged"] = false
        d["CurrentCapacity"] = 80
        XCTAssertEqual(PowerSnapshot(registry: d)?.state, .paused)
    }

    func testWithoutTelemetrySystemIsInputMinusBattery() throws {
        var d = pluggedFull
        d["PowerTelemetryData"] = ["SystemPowerIn": 20000]
        d["InstantAmperage"] = 400
        d["Voltage"] = 12500
        let s = try XCTUnwrap(PowerSnapshot(registry: d))
        XCTAssertEqual(s.systemWatts, 15, accuracy: 0.001)
    }

    func testHistoryDropsSamplesOutsideWindow() throws {
        var h = PowerHistory(window: 60)
        let base = Date(timeIntervalSince1970: 0)
        for t in stride(from: 0, through: 120, by: 10) {
            var d = pluggedFull
            d["PowerTelemetryData"] = ["SystemPowerIn": t * 100, "SystemLoad": t * 100]
            h.append(try XCTUnwrap(PowerSnapshot(registry: d, date: base.addingTimeInterval(Double(t)))))
        }
        XCTAssertEqual(h.samples.count, 7)
        XCTAssertEqual(h.samples.first?.date, base.addingTimeInterval(60))
        XCTAssertEqual(try XCTUnwrap(h.peakSystemWatts), 12, accuracy: 0.001)
    }

    func testLiveReadOnThisMac() throws {
        // Skips on a Mac without a battery.
        guard let s = BatteryReader.read() else { throw XCTSkip("no battery") }
        XCTAssertTrue((0...100).contains(s.percent))
        XCTAssertGreaterThan(s.batteryVolts, 5)
    }

    func testFormat() {
        XCTAssertEqual(PowerFormat.watts(17.625), "17.6 W")
        XCTAssertEqual(PowerFormat.watts(-12), "12.0 W")
        XCTAssertEqual(PowerFormat.watts(140.2), "140 W")
        XCTAssertEqual(PowerFormat.duration(minutes: 85), "1 小时 25 分")
        XCTAssertEqual(PowerFormat.duration(minutes: 25), "25 分")
        XCTAssertEqual(PowerFormat.duration(minutes: 85, english: true), "1 h 25 min")
    }
}

final class MergeTests: XCTestCase {
    private func base(external: Bool = true, percent: Int = 80, state: PowerSnapshot.State = .paused) -> PowerSnapshot {
        PowerSnapshot(percent: percent, state: state, externalConnected: external, inputWatts: 0, systemWatts: 0,
                      batteryWatts: 0, lossWatts: 0, batteryVolts: 12.7, batteryAmps: 0)
    }

    func testChargingFromLiveCurrent() {
        let s = base().merging(LiveReading(inputWatts: 45, systemWatts: 14, batteryVolts: 12.5, batteryAmps: 2.4, temperature: 33))
        XCTAssertEqual(s.state, .charging)
        XCTAssertEqual(s.batteryWatts, 30, accuracy: 0.001)
        // Mac = input − battery, whatever PSTR says.
        XCTAssertEqual(s.systemWatts, 15, accuracy: 0.001)
        XCTAssertEqual(s.inputWatts, s.systemWatts + s.batteryWatts, accuracy: 0.001)
        XCTAssertEqual(s.lossWatts, 0, "loss comes from the registry, not derived")
        XCTAssertEqual(s.temperature, 33)
    }

    func testAdapterTooWeakDrawsOnBattery() {
        let s = base().merging(LiveReading(inputWatts: 20, systemWatts: 30, batteryVolts: 12, batteryAmps: -0.9, temperature: nil))
        XCTAssertEqual(s.state, .assisting)
        XCTAssertEqual(s.systemWatts, 30.8, accuracy: 0.001)
    }

    func testUnplugged() {
        let s = base(external: false).merging(LiveReading(inputWatts: 0, systemWatts: 12, batteryVolts: 12, batteryAmps: -1, temperature: nil))
        XCTAssertEqual(s.state, .onBattery)
        XCTAssertEqual(s.inputWatts, 0)
        XCTAssertEqual(s.batteryWatts, -12, accuracy: 0.001)
        XCTAssertEqual(s.systemWatts, 12, accuracy: 0.001)
    }

    /// The registry can still say "unplugged" for a minute after plugging in.
    func testLiveInputMeansPluggedIn() {
        let s = base(external: false).merging(LiveReading(inputWatts: 30, systemWatts: 12, batteryVolts: 12.5, batteryAmps: 1.4, temperature: nil))
        XCTAssertTrue(s.externalConnected)
        XCTAssertEqual(s.state, .charging)
    }

    func testFullAtHundred() {
        let s = base(percent: 100, state: .full).merging(LiveReading(inputWatts: 17, systemWatts: 16, batteryVolts: 12.7, batteryAmps: 0, temperature: nil))
        XCTAssertEqual(s.state, .full)
    }

    /// A third-party 60 W PD charger reports levels but no name (2026-11-14).
    func testAdapterProfiles() throws {
        var d: [String: Any] = ["CurrentCapacity": 80, "ExternalConnected": true, "IsCharging": true,
                                "Voltage": 12260, "Amperage": 2310, "InstantAmperage": 2310]
        d["AdapterDetails"] = ["Watts": 60, "AdapterVoltage": 20000, "Current": 3000, "UsbHvcMenu": [
            ["Index": 1, "MaxCurrent": 3000, "MaxVoltage": 9000],
            ["Index": 0, "MaxCurrent": 3000, "MaxVoltage": 5000],
            ["Index": 2, "MaxCurrent": 3000, "MaxVoltage": 20000],
        ]]
        let s = try XCTUnwrap(PowerSnapshot(registry: d))
        XCTAssertNil(s.adapterName)
        XCTAssertEqual(AdapterProfile.summary(s.adapterProfiles), "5 / 9 / 20 V × 3 A")
        XCTAssertEqual(AdapterProfile.summary([.init(volts: 5, amps: 3), .init(volts: 20, amps: 2.25)]), "5 V × 3 A, 20 V × 2.25 A")
    }
}
