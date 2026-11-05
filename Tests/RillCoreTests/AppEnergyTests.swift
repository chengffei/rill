import XCTest
@testable import RillCore

final class AppEnergyTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    /// Two processes of one app at 1 W and 0.5 W for a long time → 1.5 W, heavy.
    func testGroupsByAppAndFlagsHeavy() {
        var tracker = AppEnergyTracker(timeConstant: 20)
        for step in 0...40 {
            let e = UInt64(step) * 4_000_000_000 // 4 s steps
            tracker.ingest([
                ProcessEnergy(pid: 10, energyNJ: e, appKey: "/A.app", responsiblePID: 10),        // 1 W
                ProcessEnergy(pid: 11, energyNJ: e / 2, appKey: "/A.app", responsiblePID: 10),    // 0.5 W
                ProcessEnergy(pid: 20, energyNJ: e / 10, appKey: "/B.app", responsiblePID: 20),   // 0.1 W
            ], at: t0.addingTimeInterval(Double(step) * 4))
        }
        let all = tracker.usages()
        XCTAssertEqual(all.first?.key, "/A.app")
        XCTAssertEqual(all.first?.watts ?? 0, 1.5, accuracy: 0.01)
        XCTAssertEqual(tracker.heavyApps().map(\.key), ["/A.app"])
    }

    /// A short spike is smoothed out; a heavy app stays listed until it drops below the exit level.
    func testSmoothingAndHysteresis() {
        var tracker = AppEnergyTracker(timeConstant: 20)
        var clock = t0
        var e: UInt64 = 0
        func run(_ watts: Double, _ seconds: Int) {
            for _ in 0..<(seconds / 4) {
                e += UInt64(watts * 4e9)
                clock = clock.addingTimeInterval(4)
                tracker.ingest([ProcessEnergy(pid: 1, energyNJ: e, appKey: "/A.app", responsiblePID: 1)], at: clock)
            }
        }
        tracker.ingest([ProcessEnergy(pid: 1, energyNJ: 0, appKey: "/A.app", responsiblePID: 1)], at: clock)
        run(5, 4)                       // one 4 s burst at 5 W
        XCTAssertTrue(tracker.heavyApps().isEmpty, "a 4 s burst is not sustained use")
        run(2, 80)
        XCTAssertEqual(tracker.heavyApps().map(\.key), ["/A.app"])
        run(0.8, 120)                   // between exit and enter: stays
        XCTAssertEqual(tracker.heavyApps().map(\.key), ["/A.app"])
        run(0.2, 120)
        XCTAssertTrue(tracker.heavyApps().isEmpty)
    }

    /// A reused pid whose counter restarts lower is ignored for that step.
    func testCounterResetIsIgnored() {
        var tracker = AppEnergyTracker()
        tracker.ingest([ProcessEnergy(pid: 5, energyNJ: 9_000_000_000, appKey: "/A.app", responsiblePID: 5)], at: t0)
        tracker.ingest([ProcessEnergy(pid: 5, energyNJ: 1_000, appKey: "/B.app", responsiblePID: 5)], at: t0.addingTimeInterval(4))
        XCTAssertTrue(tracker.heavyApps().isEmpty)
        XCTAssertLessThan(tracker.usages().first?.watts ?? 0, 0.01)
    }

    func testAppKey() {
        XCTAssertEqual(ProcessEnergyReader.appKey(forExecutable: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"),
                       "/Applications/Visual Studio Code.app")
        XCTAssertEqual(ProcessEnergyReader.appKey(forExecutable: "/usr/bin/swift"), "/usr/bin/swift")
    }

    func testLiveReadAttributesThisTestToItsResponsibleApp() {
        let readings = ProcessEnergyReader().read()
        XCTAssertGreaterThan(readings.count, 10)
        XCTAssertNotNil(readings.first { $0.pid == getpid() })
    }
}
