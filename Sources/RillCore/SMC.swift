import CSMC
import Foundation

/// Read-only access to the System Management Controller. Reading needs no
/// privileges; macOS 27 only gates writes to the charge-control keys.
public final class SMC {
    private let conn: io_connect_t

    public init?() {
        let c = smc_open()
        guard c != 0 else { return nil }
        conn = c
    }

    deinit { smc_close(conn) }

    public struct Value {
        public let type: String
        public let bytes: [UInt8]
    }

    public func raw(_ key: String) -> Value? {
        guard key.utf8.count == 4 else { return nil }
        var type = [CChar](repeating: 0, count: 5)
        var bytes = [UInt8](repeating: 0, count: 32)
        var size: UInt32 = 0
        let ok = key.withCString { k in smc_read(conn, k, &type, &bytes, &size) } == 0
        guard ok else { return nil }
        return Value(type: String(cString: type), bytes: Array(bytes.prefix(Int(size))))
    }

    public func double(_ key: String) -> Double? {
        raw(key).flatMap(Self.decode)
    }

    /// Decodes the numeric SMC types. On Apple silicon `flt ` and the integer
    /// types are little-endian (B0AV reads 0xC931 for 12745 mV); the legacy
    /// fixed-point types stay big-endian.
    public static func decode(_ v: Value) -> Double? {
        let b = v.bytes
        func le(_ n: Int) -> UInt64 { b.prefix(n).reversed().reduce(0) { $0 << 8 | UInt64($1) } }
        func be(_ n: Int) -> UInt64 { b.prefix(n).reduce(0) { $0 << 8 | UInt64($1) } }
        switch v.type {
        case "flt " where b.count == 4:
            return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case "ui8 " where b.count >= 1: return Double(b[0])
        case "ui16" where b.count >= 2: return Double(le(2))
        case "ui32" where b.count >= 4: return Double(le(4))
        case "si8 " where b.count >= 1: return Double(Int8(bitPattern: b[0]))
        case "si16" where b.count >= 2: return Double(Int16(bitPattern: UInt16(le(2))))
        case "si32" where b.count >= 4: return Double(Int32(bitPattern: UInt32(le(4))))
        case "sp78" where b.count >= 2: return Double(Int16(bitPattern: UInt16(be(2)))) / 256
        case "fpe2" where b.count >= 2: return Double(be(2)) / 4
        default: return nil
        }
    }

    /// Every key the SMC lists, for discovery.
    public func allKeys() -> [String] {
        let count = smc_key_count(conn)
        var keys: [String] = []
        var buf = [CChar](repeating: 0, count: 5)
        for i in 0..<count where smc_key_at(conn, i, &buf) == 0 {
            keys.append(String(cString: buf))
        }
        return keys
    }
}
