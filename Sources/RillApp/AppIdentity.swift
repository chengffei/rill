import AppKit
import RillCore

/// Name and icon for an app key, resolved once and cached.
@MainActor
enum AppIdentity {
    struct Info {
        let name: String
        let icon: NSImage
    }

    private static var cache: [String: Info] = [:]

    static func info(for usage: AppUsage) -> Info {
        if let hit = cache[usage.key] { return hit }
        let info: Info
        if let running = NSRunningApplication(processIdentifier: usage.responsiblePID),
           let name = running.localizedName {
            info = Info(name: name, icon: running.icon ?? NSWorkspace.shared.icon(forFile: usage.key))
        } else if usage.key.hasSuffix(".app") {
            let name = FileManager.default.displayName(atPath: usage.key).replacingOccurrences(of: ".app", with: "")
            info = Info(name: name, icon: NSWorkspace.shared.icon(forFile: usage.key))
        } else {
            info = Info(name: ProcessEnergyReader.displayName(forExecutable: usage.key), icon: NSWorkspace.shared.icon(forFile: usage.key))
        }
        cache[usage.key] = info
        return info
    }
}
