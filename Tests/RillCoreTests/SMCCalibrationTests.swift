import XCTest
@testable import RillCore

/// RILL_SMC_CAL=1 samples power keys each second for 65 s and compares their
/// means with the registry's minute values.
final class SMCCalibrationTests: XCTestCase {
    func testCalibrate() throws {
        guard ProcessInfo.processInfo.environment["RILL_SMC_CAL"] != nil else { throw XCTSkip("set RILL_SMC_CAL") }
        let smc = try XCTUnwrap(SMC())
        let keys = ["PDTR", "PSTR", "PPBR", "PDBR", "PHPC", "PHPS", "PZC0", "PSVR", "PMVR"]
        var sums = [String: Double](), n = 0.0
        func regValues() -> (Int, Int, Int)? {
            let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            defer { IOObjectRelease(s) }
            var p: Unmanaged<CFMutableDictionary>?
            IORegistryEntryCreateCFProperties(s, &p, kCFAllocatorDefault, 0)
            let d = p!.takeRetainedValue() as! [String: Any]
            let t = d["PowerTelemetryData"] as! [String: Any]
            return ((t["SystemPowerIn"] as! NSNumber).intValue, (t["SystemLoad"] as! NSNumber).intValue, (d["UpdateTime"] as! NSNumber).intValue)
        }
        let start = regValues()!
        var log = "start registry in=\(start.0) load=\(start.1) t=\(start.2)\n"
        var lastUpdate = start.2
        for _ in 0..<130 {
            for k in keys { sums[k, default: 0] += smc.double(k) ?? .nan }
            n += 1
            if let r = regValues(), r.2 != lastUpdate {
                lastUpdate = r.2
                log += "registry update after \(Int(n))s: in=\(r.0) load=\(r.1); smc means: " + keys.map { "\($0)=\(String(format: "%.2f", sums[$0]! / n))" }.joined(separator: " ") + "\n"
                sums = [:]; n = 0
            }
            Thread.sleep(forTimeInterval: 1)
        }
        try log.write(toFile: ProcessInfo.processInfo.environment["RILL_SMC_CAL"]!, atomically: true, encoding: .utf8)
    }
}
