import XCTest
@testable import RillCore

final class HistoryTests: XCTestCase {
    private func snap(_ t: TimeInterval, input: Double = 30, system: Double = 20, amps: Double = 0.8, temp: Double? = 33) -> PowerSnapshot {
        var s = PowerSnapshot(date: Date(timeIntervalSinceReferenceDate: t), percent: 60, state: .charging, externalConnected: true,
                              inputWatts: input, systemWatts: system, batteryWatts: 12.5 * amps, lossWatts: 0,
                              batteryVolts: 12.5, batteryAmps: amps)
        s.temperature = temp
        return s
    }

    func testAggregatorEmitsFinishedMinute() throws {
        var a = MinuteAggregator(interval: 2)
        var finished: [MinuteRecord] = []
        for t in stride(from: 600.0, to: 724, by: 2) {
            if let r = a.add(snap(t, system: t < 660 ? 20 : 40)) { finished.append(r) }
        }
        XCTAssertEqual(finished.count, 2)
        XCTAssertEqual(finished[0].t, Date(timeIntervalSinceReferenceDate: 600))
        XCTAssertEqual(finished[0].system, 20, accuracy: 0.001)
        XCTAssertEqual(finished[0].seconds, 60, accuracy: 0.001)
        XCTAssertEqual(finished[1].system, 40, accuracy: 0.001)
        let partial = try XCTUnwrap(a.partial())
        XCTAssertEqual(partial.t, Date(timeIntervalSinceReferenceDate: 720))
        XCTAssertEqual(partial.seconds, 4, accuracy: 0.001)
    }

    func testEnergyWeightsBySeconds() {
        let t = Date(timeIntervalSinceReferenceDate: 0)
        let records = [
            MinuteRecord(t: t, input: 60, system: 30, battery: 30, temp: nil, percent: 50, seconds: 60),
            MinuteRecord(t: t.addingTimeInterval(60), input: 0, system: 12, battery: -12, temp: nil, percent: 50, seconds: 30),
        ]
        let e = EnergyStats(records: records)
        XCTAssertEqual(e.inputWh, 1, accuracy: 1e-9)
        XCTAssertEqual(e.systemWh, 0.5 + 0.1, accuracy: 1e-9)
        XCTAssertEqual(e.chargedWh, 0.5, accuracy: 1e-9)
        XCTAssertEqual(e.dischargedWh, 0.1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(e.averageSystem), (30 * 60 + 12 * 30) / 90.0, accuracy: 1e-9)
        XCTAssertEqual(e.peakSystem, 30)
    }

    func testDownsampleKeepsMeanAndLimitsPoints() {
        let t = Date(timeIntervalSinceReferenceDate: 0)
        let records = (0..<1440).map { i in
            MinuteRecord(t: t.addingTimeInterval(Double(i) * 60), input: Double(i % 2) * 10, system: 10, battery: 0,
                         temp: 30, percent: 80, seconds: 60)
        }
        let out = Downsample.buckets(records, maxPoints: 300)
        XCTAssertLessThanOrEqual(out.count, 300)
        // 1440 minutes into at most 300 points gives 5-minute buckets: 0,10,0,10,0.
        XCTAssertEqual(out[0].input, 4, accuracy: 0.001)
        XCTAssertEqual(out[1].t.timeIntervalSince(out[0].t), 300)
        XCTAssertEqual(out.map(\.seconds).reduce(0, +), 1440 * 60, accuracy: 0.001)
        XCTAssertEqual(Downsample.buckets(Array(records.prefix(10)), maxPoints: 300).count, 10)
    }

    func testStoreRoundTripAndPrune() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rill-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir, keepDays: 30)
        let now = Date()
        let old = Calendar.current.date(byAdding: .day, value: -40, to: now)!
        let recent = now.addingTimeInterval(-3600)
        for d in [old, recent, now] {
            store.append(MinuteRecord(t: MinuteAggregator.minuteStart(d), input: 1, system: 2, battery: 3, temp: nil, percent: 4, seconds: 60))
        }
        XCTAssertEqual(store.load(since: now.addingTimeInterval(-7200), now: now).count, 2)
        store.prune(now: now)
        XCTAssertEqual(store.load(since: old.addingTimeInterval(-60), now: now).count, 2)
        // A torn line is skipped, not fatal.
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first)
        let h = try FileHandle(forWritingTo: file); try h.seekToEnd(); try h.write(contentsOf: Data("{\"t\":".utf8)); try h.close()
        XCTAssertEqual(store.load(since: now.addingTimeInterval(-7200), now: now).count, 2)
    }
}
