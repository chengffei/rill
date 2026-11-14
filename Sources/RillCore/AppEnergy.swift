import Darwin
import Foundation

/// Per-app CPU energy, the basis of "using significant energy".
///
/// `proc_pid_rusage(RUSAGE_INFO_V6).ri_energy_nj` counts each process's CPU
/// energy and is readable for the user's own processes without privileges
/// (root processes such as WindowServer are not apps anyway). GPU energy is
/// not attributed per process. Processes are grouped by the app responsible
/// for them, so helpers and a terminal's builds count toward that app, as in
/// Activity Monitor.
public struct AppUsage: Equatable, Sendable, Identifiable {
    /// Executable path of the responsible process; the app bundle when there is one.
    public var key: String
    public var responsiblePID: pid_t
    /// Smoothed watts.
    public var watts: Double
    /// Smoothed CPU, 100 = one core fully busy (as in Activity Monitor).
    public var cpuPercent: Double = 0
    /// Sum of the group's physical footprint, latest reading.
    public var memoryBytes: UInt64 = 0
    /// The group's busiest process in the last reading, and its name; it is
    /// often not the app itself (a terminal's `yes`, a browser's renderer).
    public var topPID: pid_t = 0
    public var topName: String = ""
    /// Set by the app layer when the window server reports the app as hung.
    public var unresponsive: Bool = false
    /// The group's processes, busiest first.
    public var processes: [ProcessUsage] = []
    public var id: String { key }

    public init(key: String, responsiblePID: pid_t, watts: Double) {
        self.key = key
        self.responsiblePID = responsiblePID
        self.watts = watts
    }
}

/// One process inside an app's group, smoothed like the group.
public struct ProcessUsage: Equatable, Sendable, Identifiable {
    public var pid: pid_t
    public var name: String
    public var watts: Double
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var id: pid_t { pid }

    public init(pid: pid_t, name: String, watts: Double, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.watts = watts
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

/// One reading of a process's counters.
public struct ProcessEnergy: Equatable, Sendable {
    public var pid: pid_t
    public var energyNJ: UInt64
    public var appKey: String
    public var responsiblePID: pid_t
    /// User plus system CPU time, nanoseconds.
    public var cpuNS: UInt64
    public var footprint: UInt64
    public var name: String

    public init(pid: pid_t, energyNJ: UInt64, appKey: String, responsiblePID: pid_t,
                cpuNS: UInt64 = 0, footprint: UInt64 = 0, name: String = "") {
        self.pid = pid
        self.energyNJ = energyNJ
        self.appKey = appKey
        self.responsiblePID = responsiblePID
        self.cpuNS = cpuNS
        self.footprint = footprint
        self.name = name
    }
}

/// Turns successive counter readings into smoothed per-app watts and decides
/// which apps count as heavy.
public struct AppEnergyTracker: Sendable {
    /// An app is heavy at or above this many watts, averaged over about
    /// `timeConstant`. Idle apps measured 0.0–0.3 W on an M1 Pro while the
    /// whole Mac drew 10–20 W (2026-11-05); 1 W is 5–10 % of that.
    public static let enterWatts = 1.0
    /// It stays listed until it falls below this, so it doesn't flicker.
    public static let exitWatts = 0.7
    public let timeConstant: TimeInterval

    private var last: [pid_t: (energy: UInt64, cpu: UInt64)] = [:]
    private var lastDate: Date?
    private var averages: [String: Double] = [:]
    private var cpuAverages: [String: Double] = [:]
    private var memory: [String: UInt64] = [:]
    private var top: [String: (pid: pid_t, name: String)] = [:]
    private var responsible: [String: pid_t] = [:]
    /// Per process: smoothed watts and CPU, and the latest reading.
    private var pidAverages: [pid_t: (watts: Double, cpu: Double)] = [:]
    private var pidLatest: [pid_t: ProcessEnergy] = [:]
    private var heavy: Set<String> = []

    public init(timeConstant: TimeInterval = 20) {
        self.timeConstant = timeConstant
    }

    /// Feeds one reading of all processes; returns every app's smoothed watts,
    /// highest first.
    @discardableResult
    public mutating func ingest(_ readings: [ProcessEnergy], at date: Date) -> [AppUsage] {
        defer { lastDate = date }
        var current: [pid_t: (energy: UInt64, cpu: UInt64)] = [:]
        var instant: [String: Double] = [:]
        var instantCPU: [String: Double] = [:]
        var topRate: [String: Double] = [:]
        var mem: [String: UInt64] = [:]
        var pidInstant: [pid_t: (watts: Double, cpu: Double)] = [:]
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        for r in readings {
            current[r.pid] = (r.energyNJ, r.cpuNS)
            responsible[r.appKey] = r.responsiblePID
            mem[r.appKey, default: 0] += r.footprint
            // A process seen for the first time has no baseline; a counter
            // that went down belongs to a reused pid.
            guard dt > 0, let before = last[r.pid], r.energyNJ >= before.energy else { continue }
            let w = Double(r.energyNJ - before.energy) / 1e9 / dt
            instant[r.appKey, default: 0] += w
            let cpu = r.cpuNS >= before.cpu ? Double(r.cpuNS - before.cpu) / 1e9 / dt * 100 : 0
            instantCPU[r.appKey, default: 0] += cpu
            pidInstant[r.pid] = (w, cpu)
            // Rank by CPU first; energy only breaks ties for processes the
            // CPU counter misses.
            let rate = cpu + w
            if rate > topRate[r.appKey] ?? -1 {
                topRate[r.appKey] = rate
                top[r.appKey] = (r.pid, r.name)
            }
        }
        last = current
        memory = mem
        pidLatest = Dictionary(readings.map { ($0.pid, $0) }, uniquingKeysWith: { _, b in b })
        guard dt > 0 else { return [] }

        let keep = 1 - exp(-dt / timeConstant)
        var nextPID: [pid_t: (watts: Double, cpu: Double)] = [:]
        for (pid, now) in pidInstant {
            let a = pidAverages[pid] ?? (0, 0)
            nextPID[pid] = (a.watts + (now.watts - a.watts) * keep, a.cpu + (now.cpu - a.cpu) * keep)
        }
        pidAverages = nextPID
        var next: [String: Double] = [:]
        var nextCPU: [String: Double] = [:]
        for key in Set(averages.keys).union(instant.keys) {
            let a = averages[key] ?? 0
            let v = a + ((instant[key] ?? 0) - a) * keep
            if v > 0.005 || instant[key] != nil {
                next[key] = v
                let c = cpuAverages[key] ?? 0
                nextCPU[key] = c + ((instantCPU[key] ?? 0) - c) * keep
            }
        }
        averages = next
        cpuAverages = nextCPU
        top = top.filter { next[$0.key] != nil }
        for (key, w) in averages {
            if w >= Self.enterWatts { heavy.insert(key) } else if w < Self.exitWatts { heavy.remove(key) }
        }
        heavy.formIntersection(averages.keys)
        return usages()
    }

    public func usages() -> [AppUsage] {
        var groups: [String: [ProcessUsage]] = [:]
        for (pid, r) in pidLatest {
            let a = pidAverages[pid] ?? (0, 0)
            groups[r.appKey, default: []].append(ProcessUsage(pid: pid, name: r.name, watts: a.watts,
                                                              cpuPercent: a.cpu, memoryBytes: r.footprint))
        }
        return averages.map { key, watts in
            var u = AppUsage(key: key, responsiblePID: responsible[key] ?? 0, watts: watts)
            u.cpuPercent = cpuAverages[key] ?? 0
            u.memoryBytes = memory[key] ?? 0
            if let t = top[key] { u.topPID = t.pid; u.topName = t.name }
            u.processes = (groups[key] ?? []).sorted {
                ($0.cpuPercent + $0.watts, $1.pid) > ($1.cpuPercent + $1.watts, $0.pid)
            }
            return u
        }
        .sorted { $0.watts > $1.watts }
    }

    /// Apps currently using significant energy, highest first.
    public func heavyApps() -> [AppUsage] {
        usages().filter { heavy.contains($0.key) }
    }
}

/// Reads every readable process's counters.
public final class ProcessEnergyReader {
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private let responsibleFor: ResponsibleFn?
    /// pid → (app key, responsible pid, name); fixed for a pid's life.
    private var cache: [pid_t: (String, pid_t, String)] = [:]
    /// rusage CPU times are Mach ticks (125/3 ns each on Apple silicon).
    private let tickNS: Double

    public init() {
        // Exported by libsystem; the same call Activity Monitor's grouping relies on.
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") {
            responsibleFor = unsafeBitCast(sym, to: ResponsibleFn.self)
        } else {
            responsibleFor = nil
        }
        var tb = mach_timebase_info()
        mach_timebase_info(&tb)
        tickNS = tb.denom == 0 ? 1 : Double(tb.numer) / Double(tb.denom)
    }

    public func read() -> [ProcessEnergy] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let got = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var out: [ProcessEnergy] = []
        out.reserveCapacity(got)
        var seen = Set<pid_t>()
        for pid in pids.prefix(got) where pid > 0 {
            var info = rusage_info_v6()
            let ok = withUnsafeMutablePointer(to: &info) { p in
                p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            } == 0
            guard ok else { continue }
            seen.insert(pid)
            let (key, resp, name): (String, pid_t, String)
            if let cached = cache[pid] {
                (key, resp, name) = cached
            } else {
                let r = responsibleFor?(pid) ?? pid
                let owner = r > 0 ? r : pid
                let own = Self.path(pid)
                key = Self.appKey(forExecutable: Self.path(owner) ?? own ?? "pid \(pid)")
                resp = owner
                name = own.map(Self.displayName(forExecutable:)) ?? "pid \(pid)"
                cache[pid] = (key, resp, name)
            }
            let ticks = info.ri_user_time &+ info.ri_system_time
            out.append(ProcessEnergy(pid: pid, energyNJ: info.ri_energy_nj, appKey: key, responsiblePID: resp,
                                     cpuNS: UInt64(Double(ticks) * tickNS), footprint: info.ri_phys_footprint, name: name))
        }
        cache = cache.filter { seen.contains($0.key) }
        return out
    }

    public static func path(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
    }

    /// A readable name for an executable. Some tools install each release as a
    /// file named after its version (Claude Code: `…/claude/versions/2.1.325`),
    /// so a version-like name falls back to the nearest folder that isn't one.
    public static func displayName(forExecutable path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard let last = parts.last else { return path }
        guard isVersionLike(last) else { return last }
        let skip: Set<String> = ["versions", "bin", "current", "libexec"]
        return parts.dropLast().reversed().first { !isVersionLike($0) && !skip.contains($0.lowercased()) } ?? last
    }

    static func isVersionLike(_ s: String) -> Bool {
        s.range(of: #"^v?\d+(\.\d+)+$"#, options: .regularExpression) != nil
    }

    /// The outermost `.app` bundle containing the executable, else the executable.
    public static func appKey(forExecutable path: String) -> String {
        guard let r = path.range(of: ".app/") else { return path }
        return String(path[..<r.lowerBound]) + ".app"
    }
}
