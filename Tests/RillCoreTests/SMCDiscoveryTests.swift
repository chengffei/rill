import XCTest
@testable import RillCore

/// RILL_SMC_DUMP=1 swift test --filter SMCDiscovery prints every numeric key
/// starting with P, B, D or TB, read twice a few seconds apart.
final class SMCDiscoveryTests: XCTestCase {
    func testDump() throws {
        guard ProcessInfo.processInfo.environment["RILL_SMC_DUMP"] != nil else { throw XCTSkip("set RILL_SMC_DUMP") }
        let smc = try XCTUnwrap(SMC())
        let keys = smc.allKeys().filter { $0.hasPrefix("P") || $0.hasPrefix("B") || $0.hasPrefix("D") || $0.hasPrefix("TB") || $0.hasPrefix("AC") }
        let first = keys.map { ($0, smc.raw($0)) }
        Thread.sleep(forTimeInterval: 4)
        var lines: [String] = []
        for (k, v) in first {
            guard let v, let a = SMC.decode(v), let b = smc.double(k) else { continue }
            lines.append("\(k) [\(v.type)] \(a) -> \(b)\(a != b ? "  *" : "")")
        }
        try lines.joined(separator: "\n").write(toFile: ProcessInfo.processInfo.environment["RILL_SMC_DUMP"]!, atomically: true, encoding: .utf8)
        print("keys total \(smc.allKeys().count), dumped \(lines.count)")
    }
}
