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

/// The click menu on a listed app: what it is using, and quit / force quit
/// for the app or its busiest process. Every action asks first.
@MainActor
enum AppActions {
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

        let appPath = ProcessEnergyReader.path(app.responsiblePID)
        let running = NSRunningApplication(processIdentifier: app.responsiblePID)
        let appAllowed = ProcessGuard.canTerminate(path: appPath, pid: app.responsiblePID)

        // The busiest process when it isn't the app itself: a terminal's
        // `yes` counts toward the terminal, but killing the terminal is the
        // wrong fix.
        if app.topPID > 0, app.topPID != app.responsiblePID, !app.topName.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled(L("占用最高的进程：\(app.topName)（pid \(app.topPID)）",
                                    "Busiest process: \(app.topName) (pid \(app.topPID))")))
            if ProcessGuard.canTerminate(path: ProcessEnergyReader.path(app.topPID), pid: app.topPID) {
                menu.addItem(action(L("结束「\(app.topName)」", "End “\(app.topName)”")) {
                    confirmSignal(SIGTERM, pid: app.topPID, name: app.topName, force: false)
                })
                menu.addItem(action(L("强制结束「\(app.topName)」", "Force End “\(app.topName)”")) {
                    confirmSignal(SIGKILL, pid: app.topPID, name: app.topName, force: true)
                })
            } else {
                menu.addItem(disabled(L("系统进程，不提供结束", "System process, can't be ended here")))
            }
        }

        menu.addItem(.separator())
        if appAllowed {
            if let running {
                menu.addItem(action(L("退出 \(info.name)", "Quit \(info.name)")) {
                    confirm(L("退出「\(info.name)」？", "Quit “\(info.name)”?"),
                            L("会像在 Dock 里选「退出」一样，应用可能先询问是否保存。",
                              "Same as Quit in the Dock; the app may ask to save first."),
                            button: L("退出", "Quit"), destructive: false) { _ = running.terminate() }
                })
                menu.addItem(action(L("强制退出 \(info.name)", "Force Quit \(info.name)")) {
                    confirm(L("强制退出「\(info.name)」？", "Force quit “\(info.name)”?"),
                            L("应用会立即关闭，未保存的内容会丢失。", "The app closes at once; unsaved changes are lost."),
                            button: L("强制退出", "Force Quit"), destructive: true) { _ = running.forceTerminate() }
                })
            } else {
                menu.addItem(action(L("结束「\(info.name)」", "End “\(info.name)”")) {
                    confirmSignal(SIGTERM, pid: app.responsiblePID, name: info.name, force: false)
                })
                menu.addItem(action(L("强制结束「\(info.name)」", "Force End “\(info.name)”")) {
                    confirmSignal(SIGKILL, pid: app.responsiblePID, name: info.name, force: true)
                })
            }
        } else {
            menu.addItem(disabled(L("系统组件或 Rill 自身，不提供退出", "Part of macOS or Rill itself, can't be quit here")))
        }

        menu.addItem(.separator())
        menu.addItem(action(L("打开活动监视器", "Open Activity Monitor")) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func confirmSignal(_ signal: Int32, pid: pid_t, name: String, force: Bool) {
        confirm(force ? L("强制结束「\(name)」？", "Force end “\(name)”?") : L("结束「\(name)」？", "End “\(name)”?"),
                force ? L("进程会立即被终止（SIGKILL），未保存的内容会丢失。", "The process is killed at once (SIGKILL); unsaved work is lost.")
                      : L("向进程发送结束请求（SIGTERM），进程可以先自行收尾。", "Asks the process to end (SIGTERM); it can clean up first."),
                button: force ? L("强制结束", "Force End") : L("结束", "End"), destructive: force) {
            if kill(pid, signal) != 0 {
                let err = String(cString: strerror(errno))
                let alert = NSAlert()
                alert.messageText = L("没能结束「\(name)」", "Couldn't end “\(name)”")
                alert.informativeText = err
                alert.runModal()
            }
        }
    }

    private static func confirm(_ title: String, _ detail: String, button: String, destructive: Bool, then run: @escaping () -> Void) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = destructive ? .critical : .warning
        let ok = alert.addButton(withTitle: button)
        ok.hasDestructiveAction = destructive
        alert.addButton(withTitle: L("取消", "Cancel")).keyEquivalent = "\u{1b}"
        if alert.runModal() == .alertFirstButtonReturn { run() }
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
