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
    public var id: String { key }
}

/// One reading of a process's energy counter.
public struct ProcessEnergy: Equatable, Sendable {
    public var pid: pid_t
    public var energyNJ: UInt64
    public var appKey: String
    public var responsiblePID: pid_t

    public init(pid: pid_t, energyNJ: UInt64, appKey: String, responsiblePID: pid_t) {
        self.pid = pid
        self.energyNJ = energyNJ
        self.appKey = appKey
        self.responsiblePID = responsiblePID
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

    private var last: [pid_t: UInt64] = [:]
    private var lastDate: Date?
    private var averages: [String: Double] = [:]
    private var responsible: [String: pid_t] = [:]
    private var heavy: Set<String> = []

    public init(timeConstant: TimeInterval = 20) {
        self.timeConstant = timeConstant
    }

    /// Feeds one reading of all processes; returns every app's smoothed watts,
    /// highest first.
    @discardableResult
    public mutating func ingest(_ readings: [ProcessEnergy], at date: Date) -> [AppUsage] {
        defer { lastDate = date }
        var current: [pid_t: UInt64] = [:]
        var instant: [String: Double] = [:]
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        for r in readings {
            current[r.pid] = r.energyNJ
            responsible[r.appKey] = r.responsiblePID
            // A process seen for the first time has no baseline; a counter
            // that went down belongs to a reused pid.
            guard dt > 0, let before = last[r.pid], r.energyNJ >= before else { continue }
            instant[r.appKey, default: 0] += Double(r.energyNJ - before) / 1e9 / dt
        }
        last = current
        guard dt > 0 else { return [] }

        let keep = 1 - exp(-dt / timeConstant)
        var next: [String: Double] = [:]
        for key in Set(averages.keys).union(instant.keys) {
            let a = averages[key] ?? 0
            let v = a + ((instant[key] ?? 0) - a) * keep
            if v > 0.005 || instant[key] != nil { next[key] = v }
        }
        averages = next
        for (key, w) in averages {
            if w >= Self.enterWatts { heavy.insert(key) } else if w < Self.exitWatts { heavy.remove(key) }
        }
        heavy.formIntersection(averages.keys)
        return usages()
    }

    public func usages() -> [AppUsage] {
        averages.map { AppUsage(key: $0.key, responsiblePID: responsible[$0.key] ?? 0, watts: $0.value) }
            .sorted { $0.watts > $1.watts }
    }

    /// Apps currently using significant energy, highest first.
    public func heavyApps() -> [AppUsage] {
        usages().filter { heavy.contains($0.key) }
    }
}

/// Reads every readable process's energy counter.
public final class ProcessEnergyReader {
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private let responsibleFor: ResponsibleFn?
    /// pid → (app key, responsible pid); paths don't change for a pid's life.
    private var cache: [pid_t: (String, pid_t)] = [:]

    public init() {
        // Exported by libsystem; the same call Activity Monitor's grouping relies on.
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") {
            responsibleFor = unsafeBitCast(sym, to: ResponsibleFn.self)
        } else {
            responsibleFor = nil
        }
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
            let (key, resp): (String, pid_t)
            if let cached = cache[pid] {
                (key, resp) = cached
            } else {
                let r = responsibleFor?(pid) ?? pid
                let owner = r > 0 ? r : pid
                key = Self.appKey(forExecutable: Self.path(owner) ?? Self.path(pid) ?? "pid \(pid)")
                resp = owner
                cache[pid] = (key, resp)
            }
            out.append(ProcessEnergy(pid: pid, energyNJ: info.ri_energy_nj, appKey: key, responsiblePID: resp))
        }
        cache = cache.filter { seen.contains($0.key) }
        return out
    }

    private static func path(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
    }

    /// The outermost `.app` bundle containing the executable, else the executable.
    public static func appKey(forExecutable path: String) -> String {
        guard let r = path.range(of: ".app/") else { return path }
        return String(path[..<r.lowerBound]) + ".app"
    }
}
