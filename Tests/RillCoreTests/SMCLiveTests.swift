import XCTest
@testable import RillCore

final class SMCLiveTests: XCTestCase {
    func testDecodeLittleEndianIntegers() {
        XCTAssertEqual(SMC.decode(.init(type: "ui16", bytes: [0x31, 0xC9])), 51505)
        XCTAssertEqual(SMC.decode(.init(type: "ui16", bytes: [0xC9, 0x31])), 12745)
        XCTAssertEqual(SMC.decode(.init(type: "si16", bytes: [0x18, 0xFC])), -1000)
        XCTAssertEqual(SMC.decode(.init(type: "flt ", bytes: [0, 0, 4, 66])), 33)
    }

    /// The SMC battery voltage must match the registry's within 0.2 V.
    func testSMCAgreesWithRegistry() throws {
        guard let smc = SMC(), let reg = BatteryReader.read(),
              let mv = smc.double("B0AV") else { throw XCTSkip("no SMC or battery") }
        XCTAssertEqual(mv / 1000, reg.batteryVolts, accuracy: 0.2)
        if let t = smc.double("TB0T") { XCTAssertTrue((10...60).contains(t), "TB0T \(t)") }
        if let input = smc.double("PDTR"), reg.externalConnected { XCTAssertGreaterThan(input, 0) }
    }
}
