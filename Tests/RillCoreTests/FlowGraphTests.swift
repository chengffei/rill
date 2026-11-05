import XCTest
@testable import RillCore

final class FlowGraphTests: XCTestCase {
    private func snap(external: Bool, input: Double, system: Double, battery: Double) -> PowerSnapshot {
        PowerSnapshot(percent: 60, state: .charging, externalConnected: external, inputWatts: input, systemWatts: system,
                      batteryWatts: battery, lossWatts: 0, batteryVolts: 12.5, batteryAmps: battery / 12.5)
    }

    func testChargingSplitsAdapterIntoBatteryAndMac() {
        let g = FlowGraph(snap(external: true, input: 36, system: 22.5, battery: 13))
        XCTAssertEqual(g.sources.map(\.role), [.adapter])
        XCTAssertEqual(g.sinks.map(\.role), [.battery, .mac])
        XCTAssertEqual(g.links, [.init(from: 0, to: 0, watts: 13), .init(from: 0, to: 1, watts: 22.5)])
    }

    func testFullBatteryLeavesTheGraph() {
        let g = FlowGraph(snap(external: true, input: 17, system: 16.5, battery: 0))
        XCTAssertEqual(g.sinks.map(\.role), [.mac])
        XCTAssertEqual(g.links, [.init(from: 0, to: 0, watts: 16.5)])
    }

    func testWeakAdapterMergesWithBattery() {
        let g = FlowGraph(snap(external: true, input: 20, system: 30, battery: -10))
        XCTAssertEqual(g.sources.map(\.role), [.adapter, .battery])
        XCTAssertEqual(g.sinks.map(\.role), [.mac])
        XCTAssertEqual(g.links, [.init(from: 0, to: 0, watts: 20), .init(from: 1, to: 0, watts: 10)])
    }

    func testOnBattery() {
        let g = FlowGraph(snap(external: false, input: 0, system: 12, battery: -12))
        XCTAssertEqual(g.sources.map(\.role), [.battery])
        XCTAssertEqual(g.links, [.init(from: 0, to: 0, watts: 12)])
    }
}
