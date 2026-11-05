import XCTest
@testable import RillCore

/// RILL_CHARGE_CAL=1: while charging, prints SMC keys beside the registry's
/// telemetry for 20 s to pin down what PSTR counts.
final class ChargeCalTests: XCTestCase {
    func testCompare() throws {
        guard ProcessInfo.processInfo.environment["RILL_CHARGE_CAL"] != nil else { throw XCTSkip("set RILL_CHARGE_CAL") }
        let smc = try XCTUnwrap(SMC())
        let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        defer { IOObjectRelease(s) }
        var p: Unmanaged<CFMutableDictionary>?
        IORegistryEntryCreateCFProperties(s, &p, kCFAllocatorDefault, 0)
        let d = p!.takeRetainedValue() as! [String: Any]
        let t = d["PowerTelemetryData"] as! [String: Any]
        print("registry", ["SystemPowerIn", "SystemLoad", "BatteryPower", "AdapterEfficiencyLoss", "SystemEnergyConsumed"].map { "\($0)=\(t[$0] ?? "-")" }.joined(separator: " "),
              "InstantAmperage=\(d["InstantAmperage"] ?? "-") Voltage=\(d["Voltage"] ?? "-")")
        var sums = [String: Double](); let keys = ["PDTR", "PSTR", "PPBR", "PDBR", "B0AV", "B0AC", "PHPC", "PZC0", "PMVR", "PSVR"]
        for _ in 0..<20 { for k in keys { sums[k, default: 0] += smc.double(k) ?? .nan }; Thread.sleep(forTimeInterval: 1) }
        print("smc means", keys.map { "\($0)=\(String(format: "%.2f", sums[$0]! / 20))" }.joined(separator: " "))
    }
}
