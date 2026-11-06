import AppKit
import RillCore

/// Apps the window server reports as not responding — the same flag behind
/// Activity Monitor's "(Not Responding)" and the spinning cursor. The calls
/// are private (CoreGraphics/SkyLight), looked up at run time; if they go
/// away, detection is simply off. Checked on macOS 27 (2026-11-06).
@MainActor
final class HangDetector {
    private typealias ConnFn = @convention(c) () -> Int32
    private typealias UnresponsiveFn = @convention(c) (Int32, UnsafePointer<ProcessSerialNumber>) -> Bool
    private typealias PSNFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private let connection: ConnFn?
    private let isUnresponsive: UnresponsiveFn?
    private let psnFor: PSNFn?
    /// Seen hung in the previous check; an app counts only after two checks
    /// in a row (about 4 s), so a brief beach ball doesn't list it.
    private var suspect: Set<pid_t> = []

    init() {
        let h = UnsafeMutableRawPointer(bitPattern: -2)
        connection = dlsym(h, "CGSMainConnectionID").map { unsafeBitCast($0, to: ConnFn.self) }
        isUnresponsive = dlsym(h, "CGSEventIsAppUnresponsive").map { unsafeBitCast($0, to: UnresponsiveFn.self) }
        psnFor = dlsym(h, "GetProcessForPID").map { unsafeBitCast($0, to: PSNFn.self) }
    }

    /// Regular (Dock) apps that have been unresponsive for two checks.
    func check() -> [NSRunningApplication] {
        guard let connection, let isUnresponsive, let psnFor else { return [] }
        let cid = connection()
        var now: Set<pid_t> = []
        var hung: [NSRunningApplication] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            var psn = ProcessSerialNumber()
            guard psnFor(app.processIdentifier, &psn) == noErr, isUnresponsive(cid, &psn) else { continue }
            now.insert(app.processIdentifier)
            if suspect.contains(app.processIdentifier) { hung.append(app) }
        }
        suspect = now
        return hung
    }
}

/// Quitting apps and ending processes, shared by the panel's click menu,
/// the Apps table and the Process menu. Every action asks first, the way
/// Activity Monitor does: one alert offering Quit, Force Quit or Cancel.
@MainActor
enum AppActions {
    static func canQuit(_ app: AppUsage) -> Bool {
        ProcessGuard.canTerminate(path: ProcessEnergyReader.path(app.responsiblePID), pid: app.responsiblePID)
    }

    /// The group's busiest process when it isn't the app itself: a
    /// terminal's `yes` counts toward the terminal, but quitting the
    /// terminal is the wrong fix.
    static func busiestOtherProcess(_ app: AppUsage) -> (pid: pid_t, name: String)? {
        guard app.topPID > 0, app.topPID != app.responsiblePID, !app.topName.isEmpty,
              ProcessGuard.canTerminate(path: ProcessEnergyReader.path(app.topPID), pid: app.topPID) else { return nil }
        return (app.topPID, app.topName)
    }

    static func confirmQuit(_ app: AppUsage) {
        guard canQuit(app) else { return }
        let name = AppIdentity.info(for: app).name
        let running = NSRunningApplication(processIdentifier: app.responsiblePID)
        ask(L("要退出「\(name)」吗？", "Are you sure you want to quit “\(name)”?"),
            app.unresponsive ? L("这个应用没有响应，「退出」可能无效，可以选「强制退出」，未存储的更改会丢失。",
                                 "This app isn't responding, so Quit may not work. Force Quit closes it at once and loses unsaved changes.")
                             : L("「强制退出」会立即关闭应用，未存储的更改会丢失。", "Force Quit closes the app at once and loses unsaved changes."),
            primary: L("退出", "Quit"), force: L("强制退出", "Force Quit")) { force in
            if let running {
                _ = force ? running.forceTerminate() : running.terminate()
            } else {
                signal(force ? SIGKILL : SIGTERM, pid: app.responsiblePID, name: name)
            }
        }
    }

    static func endProcess(pid: pid_t, name: String) {
        ask(L("要结束进程「\(name)」吗？", "Are you sure you want to end “\(name)”?"),
            L("「结束」请进程自行退出；「强制结束」立即终止，未存储的内容会丢失。",
              "End asks the process to exit; Force End stops it at once and loses unsaved work."),
            primary: L("结束", "End"), force: L("强制结束", "Force End")) { force in
            signal(force ? SIGKILL : SIGTERM, pid: pid, name: name)
        }
    }

    static func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }

    /// The panel's click menu: what the app is using, then the actions.
    static func showMenu(for app: AppUsage) {
        let info = AppIdentity.info(for: app)
        let menu = NSMenu()
        menu.autoenablesItems = false

        var facts: [String] = []
        if app.unresponsive { facts.append(L("未响应", "Not responding")) }
        facts.append(PowerFormat.watts(app.watts))
        facts.append("CPU \(Format.cpu(app.cpuPercent))")
        if app.memoryBytes > 0 { facts.append(L("内存 ", "Memory ") + Format.bytes(app.memoryBytes)) }
        menu.addItem(disabled("\(info.name) · " + facts.joined(separator: " · ")))
        menu.addItem(.separator())

        if canQuit(app) {
            menu.addItem(action(L("退出 \(info.name)…", "Quit \(info.name)…")) { confirmQuit(app) })
        } else {
            menu.addItem(disabled(L("系统组件或 Rill 自身，不提供退出", "Part of macOS or Rill itself, can't be quit here")))
        }
        if let top = busiestOtherProcess(app) {
            menu.addItem(action(L("结束「\(top.name)」…", "End “\(top.name)”…")) { endProcess(pid: top.pid, name: top.name) })
        }
        menu.addItem(.separator())
        menu.addItem(action(L("打开活动监视器", "Open Activity Monitor")) { openActivityMonitor() })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Alert with the default action, Cancel, and the forceful action on the
    /// leading side, as in Activity Monitor.
    private static func ask(_ title: String, _ detail: String, primary: String, force: String, then run: @escaping (_ force: Bool) -> Void) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: primary)
        alert.addButton(withTitle: L("取消", "Cancel")).keyEquivalent = "\u{1b}"
        let f = alert.addButton(withTitle: force)
        f.hasDestructiveAction = true
        switch alert.runModal() {
        case .alertFirstButtonReturn: run(false)
        case .alertThirdButtonReturn: run(true)
        default: break
        }
    }

    private static func signal(_ sig: Int32, pid: pid_t, name: String) {
        guard kill(pid, sig) != 0 else { return }
        let alert = NSAlert()
        alert.messageText = L("没能结束「\(name)」", "Couldn't end “\(name)”")
        alert.informativeText = String(cString: strerror(errno))
        alert.runModal()
    }

    private static func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func action(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuTarget.fire(_:)), keyEquivalent: "")
        item.target = MenuTarget.shared
        item.representedObject = MenuTarget.Box(run)
        return item
    }
}

@MainActor
final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    final class Box: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    @objc func fire(_ sender: NSMenuItem) {
        // Let the menu close before a modal alert opens.
        let box = sender.representedObject as? Box
        DispatchQueue.main.async { box?.run() }
    }
}

enum Format {
    static func cpu(_ percent: Double) -> String {
        percent >= 10 ? String(format: "%.0f%%", percent) : String(format: "%.1f%%", percent)
    }

    static func bytes(_ b: UInt64) -> String {
        let mb = Double(b) / 1_048_576
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}
