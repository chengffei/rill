import Foundation

/// Which processes Rill offers to quit or kill. Only the user's own processes
/// are reachable anyway (no privileged helper); on top of that, macOS's own
/// user-session pieces (Finder, Dock, loginwindow, daemons) are left alone,
/// since killing them logs out, blanks the desktop or just respawns them.
public enum ProcessGuard {
    static let protectedPrefixes = [
        "/System/",
        "/usr/libexec/",
        "/usr/sbin/",
        "/sbin/",
        "/Library/Apple/",
    ]

    public static func canTerminate(path: String?, pid: pid_t, selfPID: pid_t = getpid()) -> Bool {
        guard pid > 1, pid != selfPID, let path, path.hasPrefix("/") else { return false }
        return !protectedPrefixes.contains { path.hasPrefix($0) }
    }
}
