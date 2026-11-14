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

final class AppEnergyDetailTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    /// CPU is summed per app (100 = one core); the busiest process is named; memory is the latest sum.
    func testCPUMemoryAndTopProcess() {
        var tracker = AppEnergyTracker(timeConstant: 20)
        for step in 0...40 {
            let s = UInt64(step) * 4
            tracker.ingest([
                ProcessEnergy(pid: 10, energyNJ: s * 100_000_000, appKey: "/Code.app", responsiblePID: 10,
                              cpuNS: s * 50_000_000, footprint: 300 << 20, name: "Code"),          // 5 % CPU
                ProcessEnergy(pid: 42, energyNJ: s * 3_000_000_000, appKey: "/Code.app", responsiblePID: 10,
                              cpuNS: s * 1_000_000_000, footprint: 1 << 20, name: "yes"),          // 100 % CPU
            ], at: t0.addingTimeInterval(Double(step) * 4))
        }
        let a = tracker.usages().first
        XCTAssertEqual(a?.cpuPercent ?? 0, 105, accuracy: 1)
        XCTAssertEqual(a?.memoryBytes, (300 << 20) + (1 << 20))
        XCTAssertEqual(a?.topPID, 42)
        XCTAssertEqual(a?.topName, "yes")
    }

    func testGuard() {
        XCTAssertTrue(ProcessGuard.canTerminate(path: "/Applications/Figma.app", pid: 500, selfPID: 1))
        XCTAssertTrue(ProcessGuard.canTerminate(path: "/usr/bin/yes", pid: 500, selfPID: 1))
        XCTAssertFalse(ProcessGuard.canTerminate(path: "/System/Library/CoreServices/Finder.app", pid: 500, selfPID: 1))
        XCTAssertFalse(ProcessGuard.canTerminate(path: "/usr/libexec/trustd", pid: 500, selfPID: 1))
        XCTAssertFalse(ProcessGuard.canTerminate(path: "/Applications/Rill.app", pid: 500, selfPID: 500))
        XCTAssertFalse(ProcessGuard.canTerminate(path: "pid 77", pid: 77, selfPID: 1))
    }

    func testLiveReadHasCPUAndFootprint() {
        let me = ProcessEnergyReader().read().first { $0.pid == getpid() }
        XCTAssertGreaterThan(me?.footprint ?? 0, 1 << 20)
        XCTAssertGreaterThan(me?.cpuNS ?? 0, 0)
    }

    /// Each group lists its processes, smoothed on their own, busiest first.
    func testProcessesPerGroup() {
        var tracker = AppEnergyTracker(timeConstant: 20)
        for step in 0...40 {
            let s = UInt64(step) * 4
            tracker.ingest([
                ProcessEnergy(pid: 10, energyNJ: s * 100_000_000, appKey: "/Code.app", responsiblePID: 10,
                              cpuNS: s * 50_000_000, footprint: 300 << 20, name: "Code"),
                ProcessEnergy(pid: 42, energyNJ: s * 3_000_000_000, appKey: "/Code.app", responsiblePID: 10,
                              cpuNS: s * 1_000_000_000, footprint: 1 << 20, name: "yes"),
            ], at: t0.addingTimeInterval(Double(step) * 4))
        }
        let p = tracker.usages().first?.processes ?? []
        XCTAssertEqual(p.map(\.pid), [42, 10])
        XCTAssertEqual(p.first?.cpuPercent ?? 0, 100, accuracy: 1)
        XCTAssertEqual(p.first?.watts ?? 0, 3, accuracy: 0.05)
        XCTAssertEqual(p.last?.memoryBytes, 300 << 20)
    }

    /// Executables named after their version get a folder's name instead.
    func testDisplayName() {
        XCTAssertEqual(ProcessEnergyReader.displayName(forExecutable: "/Users/a/.local/share/claude/versions/2.1.325"), "claude")
        XCTAssertEqual(ProcessEnergyReader.displayName(forExecutable: "/opt/tool/v1.2/bin/1.2.3"), "tool")
        XCTAssertEqual(ProcessEnergyReader.displayName(forExecutable: "/usr/bin/yes"), "yes")
        XCTAssertEqual(ProcessEnergyReader.displayName(forExecutable: "/x/node22"), "node22")
    }
}
