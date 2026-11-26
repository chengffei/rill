import Foundation

/// An app holding a lot of memory that hasn't been in front for a while.
public struct IdleMemoryApp: Equatable, Sendable, Identifiable {
    public var usage: AppUsage
    /// Last time the app was frontmost, or when Rill first saw it.
    public var lastActive: Date
    public var id: String { usage.key }

    public init(usage: AppUsage, lastActive: Date) {
        self.usage = usage
        self.lastActive = lastActive
    }
}

/// Finds apps worth quitting to free memory: big and unused.
///
/// Most of such an app's memory is usually already compressed or swapped
/// (2026-11-26 on a 16 GB Mac: Chrome's renderers 3.2 GB, Figma 1.4 GB,
/// Lark 1.1 GB, nearly all compressed). macOS can't free it; quitting can.
/// "Unused" means not frontmost; an app seen for the first time counts
/// from then, so nothing is listed in Rill's first 30 minutes.
public struct IdleMemoryTracker: Sendable {
    public static let minBytes: UInt64 = 1 << 30
    public static let idleAfter: TimeInterval = 30 * 60

    private var lastActive: [String: Date] = [:]
    private let idleAfter: TimeInterval

    public init(idleAfter: TimeInterval = IdleMemoryTracker.idleAfter) {
        self.idleAfter = idleAfter
    }

    /// The app in front now (or just activated).
    public mutating func noteActive(_ key: String, at date: Date) {
        lastActive[key] = date
    }

    /// A running app, at Rill's start or at its launch: the clock starts
    /// unless it already has.
    public mutating func noteSeen(_ key: String, at date: Date) {
        if lastActive[key] == nil { lastActive[key] = date }
    }

    /// The app quit; a relaunch counts from scratch.
    public mutating func forget(_ key: String) {
        lastActive[key] = nil
    }

    /// Of the given candidates (Dock apps that can be quit), those at or
    /// above `minBytes` and not in front for `idleAfter`, largest first.
    public mutating func idle(among apps: [AppUsage], at now: Date) -> [IdleMemoryApp] {
        var out: [IdleMemoryApp] = []
        for u in apps {
            noteSeen(u.key, at: now)
            let since = lastActive[u.key] ?? now
            if u.memoryBytes >= Self.minBytes, now.timeIntervalSince(since) >= idleAfter {
                out.append(IdleMemoryApp(usage: u, lastActive: since))
            }
        }
        return out.sorted { $0.usage.memoryBytes > $1.usage.memoryBytes }
    }
}

extension SystemLoad {
    /// Memory is short enough to suggest quitting idle apps. Apple silicon
    /// rarely leaves the normal pressure level (it read normal with 5.3 GB
    /// swapped on a 16 GB Mac, 2026-11-26), so a swap of a quarter of RAM
    /// or more counts too.
    public var memoryTight: Bool {
        pressure != .normal || swapUsed >= memoryTotal / 4
    }
}
