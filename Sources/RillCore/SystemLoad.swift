import Darwin
import Foundation

/// Whole-machine load for the Apps page, the numbers at the bottom of
/// Activity Monitor: CPU split into user and system, load average, memory
/// used the way Activity Monitor counts it, swap and memory pressure.
public struct SystemLoad: Equatable, Sendable {
    /// Share of all cores, 0–100. Nil until two readings give a rate.
    public var cpuUser: Double?
    public var cpuSystem: Double?
    public var cores: Int
    /// 1, 5 and 15 minutes.
    public var loadAverage: [Double]
    /// App memory (anonymous minus purgeable), wired and compressed pages.
    public var memoryApp: UInt64
    public var memoryWired: UInt64
    public var memoryCompressed: UInt64
    public var memoryTotal: UInt64
    public var swapUsed: UInt64
    public var pressure: MemoryPressure

    public var cpuTotal: Double? { cpuUser.flatMap { u in cpuSystem.map { u + $0 } } }
    /// Activity Monitor's "Memory Used".
    public var memoryUsed: UInt64 { memoryApp + memoryWired + memoryCompressed }
    /// The load in busy cores, comparable with the per-process CPU column
    /// (where 100 % is one core).
    public var busyCores: Double? { cpuTotal.map { $0 / 100 * Double(cores) } }

    public init(cpuUser: Double?, cpuSystem: Double?, cores: Int, loadAverage: [Double],
                memoryApp: UInt64, memoryWired: UInt64, memoryCompressed: UInt64, memoryTotal: UInt64,
                swapUsed: UInt64, pressure: MemoryPressure) {
        self.cpuUser = cpuUser
        self.cpuSystem = cpuSystem
        self.cores = cores
        self.loadAverage = loadAverage
        self.memoryApp = memoryApp
        self.memoryWired = memoryWired
        self.memoryCompressed = memoryCompressed
        self.memoryTotal = memoryTotal
        self.swapUsed = swapUsed
        self.pressure = pressure
    }
}

/// kern.memorystatus_vm_pressure_level, the level Activity Monitor colours
/// its memory pressure graph by.
public enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4
}

/// Cumulative CPU ticks of all cores from HOST_CPU_LOAD_INFO. They are 32-bit
/// and wrap, so deltas use wrapping subtraction.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }

    /// User (with nice) and system shares in percent between two readings.
    public static func share(from a: CPUTicks, to b: CPUTicks) -> (user: Double, system: Double)? {
        let user = Double(b.user &- a.user) + Double(b.nice &- a.nice)
        let system = Double(b.system &- a.system)
        let total = user + system + Double(b.idle &- a.idle)
        guard total > 0 else { return nil }
        return (user / total * 100, system / total * 100)
    }
}

public final class SystemLoadReader {
    private let host = mach_host_self()
    private let pageSize = UInt64(getpagesize())
    private var lastTicks: CPUTicks?

    public init() {}

    public func read() -> SystemLoad {
        var cpu: (user: Double, system: Double)?
        if let ticks = cpuTicks() {
            if let last = lastTicks { cpu = CPUTicks.share(from: last, to: ticks) }
            lastTicks = ticks
        }
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) != 3 { load = [] }
        let vm = vmStats()
        return SystemLoad(
            cpuUser: cpu?.user, cpuSystem: cpu?.system,
            cores: ProcessInfo.processInfo.activeProcessorCount,
            loadAverage: load,
            memoryApp: vm.map { UInt64($0.internal_page_count) &- min(UInt64($0.internal_page_count), UInt64($0.purgeable_count)) }.map { $0 * pageSize } ?? 0,
            memoryWired: vm.map { UInt64($0.wire_count) * pageSize } ?? 0,
            memoryCompressed: vm.map { UInt64($0.compressor_page_count) * pageSize } ?? 0,
            memoryTotal: ProcessInfo.processInfo.physicalMemory,
            swapUsed: swapUsed(),
            pressure: pressure()
        )
    }

    private func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks // user, system, idle, nice
        return CPUTicks(user: t.0, system: t.1, idle: t.2, nice: t.3)
    }

    private func vmStats() -> vm_statistics64? {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? vm : nil
    }

    private func swapUsed() -> UInt64 {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        return sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 ? swap.xsu_used : 0
    }

    private func pressure() -> MemoryPressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }
}
