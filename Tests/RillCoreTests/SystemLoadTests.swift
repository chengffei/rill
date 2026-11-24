import XCTest
@testable import RillCore

final class SystemLoadTests: XCTestCase {
    func testShareCountsNiceAsUser() {
        let a = CPUTicks(user: 100, system: 50, idle: 800, nice: 0)
        let b = CPUTicks(user: 160, system: 70, idle: 900, nice: 20)
        let s = CPUTicks.share(from: a, to: b)!
        XCTAssertEqual(s.user, 40, accuracy: 0.001)   // (60 + 20) / 200
        XCTAssertEqual(s.system, 10, accuracy: 0.001) // 20 / 200
    }

    func testShareSurvivesWrap() {
        let a = CPUTicks(user: .max - 9, system: 0, idle: 0, nice: 0)
        let b = CPUTicks(user: 10, system: 0, idle: 20, nice: 0)
        XCTAssertEqual(CPUTicks.share(from: a, to: b)!.user, 50, accuracy: 0.001)
    }

    func testNoTimePassedGivesNil() {
        let a = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        XCTAssertNil(CPUTicks.share(from: a, to: a))
    }

    func testLiveReadingIsSane() {
        let r = SystemLoadReader()
        XCTAssertNil(r.read().cpuTotal, "first reading has no interval")
        usleep(200_000)
        let s = r.read()
        let cpu = try! XCTUnwrap(s.cpuTotal)
        XCTAssert((0...100).contains(cpu))
        XCTAssertEqual(s.loadAverage.count, 3)
        XCTAssertGreaterThan(s.memoryUsed, 0)
        XCTAssertLessThan(s.memoryUsed, s.memoryTotal)
    }
}
