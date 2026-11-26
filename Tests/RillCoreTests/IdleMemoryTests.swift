import XCTest
@testable import RillCore

final class IdleMemoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private let gb: UInt64 = 1 << 30

    private func app(_ key: String, _ bytes: UInt64) -> AppUsage {
        var u = AppUsage(key: key, responsiblePID: 1, watts: 0)
        u.memoryBytes = bytes
        return u
    }

    func testListsBigAppsIdleForHalfAnHour() {
        var t = IdleMemoryTracker()
        let apps = [app("/Big.app", 2 * gb), app("/Small.app", gb / 2), app("/Bigger.app", 3 * gb)]
        XCTAssertTrue(t.idle(among: apps, at: t0).isEmpty, "first sight starts the clock")
        XCTAssertTrue(t.idle(among: apps, at: t0.addingTimeInterval(29 * 60)).isEmpty)
        let idle = t.idle(among: apps, at: t0.addingTimeInterval(30 * 60))
        XCTAssertEqual(idle.map(\.id), ["/Bigger.app", "/Big.app"], "largest first, small app left out")
        XCTAssertEqual(idle.first?.lastActive, t0)
    }

    func testBeingInFrontResetsTheClock() {
        var t = IdleMemoryTracker()
        let apps = [app("/Big.app", 2 * gb)]
        t.noteSeen("/Big.app", at: t0)
        t.noteSeen("/Big.app", at: t0.addingTimeInterval(10 * 60)) // no effect once started
        t.noteActive("/Big.app", at: t0.addingTimeInterval(20 * 60))
        XCTAssertTrue(t.idle(among: apps, at: t0.addingTimeInterval(40 * 60)).isEmpty)
        XCTAssertEqual(t.idle(among: apps, at: t0.addingTimeInterval(50 * 60)).count, 1)
    }

    func testQuitAppIsForgotten() {
        var t = IdleMemoryTracker()
        _ = t.idle(among: [app("/Big.app", 2 * gb)], at: t0)
        t.forget("/Big.app")
        t.noteSeen("/Big.app", at: t0.addingTimeInterval(20 * 60))
        // Relaunched: counts from its return, not from t0.
        XCTAssertTrue(t.idle(among: [app("/Big.app", 2 * gb)], at: t0.addingTimeInterval(31 * 60)).isEmpty)
    }

    func testMemoryTight() {
        func load(_ p: MemoryPressure, swap: UInt64) -> SystemLoad {
            SystemLoad(cpuUser: nil, cpuSystem: nil, cores: 8, loadAverage: [], memoryApp: 0, memoryWired: 0,
                       memoryCompressed: 0, memoryTotal: 16 * gb, swapUsed: swap, pressure: p)
        }
        XCTAssertFalse(load(.normal, swap: 3 * gb).memoryTight)
        XCTAssertTrue(load(.normal, swap: 4 * gb).memoryTight)
        XCTAssertTrue(load(.warning, swap: 0).memoryTight)
    }
}
