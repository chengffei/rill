import AppKit
import Combine
import RillCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PowerModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var dashboard: NSWindow?
    private var settingsWindow: NSWindow?
    private let settings = AppSettings.shared
    private var subscriptions: Set<AnyCancellable> = []
    private var shownSymbol = ""
    private var shownTitle = ""
    private var appearanceObservation: NSKeyValueObservation?

    private func syncPopoverAppearance() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        popover.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    /// Launching Rill again (Finder, Spotlight) opens the Dashboard; there is no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openDashboard()
        return false
    }

    /// The main window: sidebar pages in a standard unified toolbar window.
    /// The title is the current page (Apple: don't title windows with the
    /// app name); SwiftUI's navigationTitle and toolbar reach it by bridging.
    func openDashboard() {
        if dashboard == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            let hosting = NSHostingController(rootView: DashboardView(model: model))
            hosting.sceneBridgingOptions = .all
            w.contentViewController = hosting
            w.setContentSize(NSSize(width: 980, height: 680))
            w.center()
            w.setFrameAutosaveName("RillMainWindow")
            w.delegate = self
            dashboard = w
        }
        model.dashboardVisible = true
        showInDock(true)
        NSApp.activate(ignoringOtherApps: true)
        dashboard?.makeKeyAndOrderFront(nil)
    }

    /// Settings: one pane, so the title is "Rill Settings"; minimize and zoom
    /// stay dimmed; opened from the app menu or ⌘, (Apple HIG, Settings).
    func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.title = L("Rill 设置", "Rill Settings")
            w.center()
            w.setFrameAutosaveName("RillSettings")
            w.delegate = self
            settingsWindow = w
        }
        showInDock(true)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Rill is a menu bar app with no Dock icon. While one of its windows is
    /// open it becomes a regular app, so the window gets a Dock icon, ⌘-Tab
    /// and the app menu (where Settings… and the commands live); when the
    /// last window closes it goes back to the menu bar only.
    private func showInDock(_ on: Bool) {
        let policy: NSApplication.ActivationPolicy = on ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if on { NSApp.mainMenu = MainMenu.build(target: self) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        popover.delegate = self
        popover.behavior = .transient
        popover.animates = false
        // Light, dark or system by the Appearance setting (2026-11-08). The
        // popover gets it explicitly: left nil it would follow the status
        // item's window, which is dark over a dark wallpaper even in light mode.
        settings.applyAppearance()
        syncPopoverAppearance()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.syncPopoverAppearance() }
        }
        let hosting = NSHostingController(rootView: PopoverView(model: model, onOpenDashboard: { [weak self] in
            self?.popover.performClose(nil)
            self?.openDashboard()
        }))
        // Size the popover ourselves. Letting SwiftUI resize it after it was
        // shown grew the window upward from its bottom edge, pushing the top
        // 260 pt off screen (2026-11-04).
        hosting.sizingOptions = []
        popover.contentViewController = hosting

        model.onUpdate = { [weak self] in
            self?.updateStatusItem($0)
            self?.fitPopover()
        }
        model.start()
        settings.$showsPower.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.shownTitle = "\u{0}"
            self.updateStatusItem(self.lastSnapshot)
        }.store(in: &subscriptions)
        settings.$language.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.settingsWindow?.title = L("Rill 设置", "Rill Settings")
            if NSApp.activationPolicy() == .regular { NSApp.mainMenu = MainMenu.build(target: self) }
            self.fitPopover()
        }.store(in: &subscriptions)
        // Debug: RILL_FLOW_PREVIEW=/path.png renders the flow for five sample
        // states (charging, full, adapter too weak, on battery, trickle charge) and quits.
        if let path = ProcessInfo.processInfo.environment["RILL_FLOW_PREVIEW"] {
            func sample(_ ext: Bool, _ input: Double, _ sys: Double, _ bat: Double, _ pct: Int) -> PowerSnapshot {
                PowerSnapshot(percent: pct, state: .charging, externalConnected: ext, inputWatts: input, systemWatts: sys,
                              batteryWatts: bat, lossWatts: 0, batteryVolts: 12.5, batteryAmps: bat / 12.5)
            }
            let samples = [sample(true, 36, 22.55, 13, 62), sample(true, 17.2, 16.5, 0, 100),
                           sample(true, 20, 31, -11, 70), sample(false, 0, 12.4, -12.4, 45),
                           sample(true, 25, 23, 2, 96)]
            let view = VStack(spacing: 14) {
                ForEach(0..<samples.count, id: \.self) { i in
                    FlowView(snapshot: samples[i]).frame(width: 332).glassCard()
                }
            }
            .padding(16).background(Color(white: 0.93)).environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let cg = renderer.cgImage {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }

        // Debug: RILL_OPEN_DASHBOARD=apps (or overview, history, battery) opens
        // the main window on that page at launch, for screenshots.
        if let page = ProcessInfo.processInfo.environment["RILL_OPEN_DASHBOARD"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if let p = DashboardPage(rawValue: page) { DashboardState.shared.page = p }
                self?.openDashboard()
            }
        }

        // Debug: RILL_OPEN_SETTINGS=1 opens the Settings window at launch, for screenshots.
        if ProcessInfo.processInfo.environment["RILL_OPEN_SETTINGS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.openSettings() }
        }

        // Debug: RILL_OPEN_POPOVER=1 opens the panel 2.5 s after launch, for
        // screenshots; a number instead of 1 is the delay in seconds.
        if let value = ProcessInfo.processInfo.environment["RILL_OPEN_POPOVER"] {
            let delay = Double(value).flatMap { $0 > 1 ? $0 : nil } ?? 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                self.statusItemClicked(button)
            }
        }
        if ProcessInfo.processInfo.environment["RILL_DEBUG"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                let w = self?.statusItem.button?.window
                print("status item frame=\(w?.frame ?? .zero) visible=\(w?.isVisible ?? false) occluded=\(w.map { !$0.occlusionState.contains(.visible) } ?? true) isVisible=\(self?.statusItem.isVisible ?? false)")
                fflush(stdout)
            }
        }

        // Debug: RILL_SNAPSHOT=/path.png renders the panel after a few samples and
        // quits. The main window is captured with screencapture -l instead.
        if let path = ProcessInfo.processInfo.environment["RILL_SNAPSHOT"] {
            model.popoverVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [model] in
                let content = PopoverView(model: model, onOpenDashboard: {})
                let renderer = ImageRenderer(content: content.environment(\.colorScheme, .light))
                renderer.scale = 2
                if let cg = renderer.cgImage {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
        }
    }

    private var showsPower: Bool { settings.showsPower }
    private var lastSnapshot: PowerSnapshot?

    private func updateStatusItem(_ s: PowerSnapshot?) {
        lastSnapshot = s
        guard let button = statusItem.button else { return }
        guard let s else {
            button.image = NSImage(systemSymbolName: "bolt.slash", accessibilityDescription: nil)
            button.title = ""
            shownSymbol = ""
            return
        }
        let mark: BatteryGlyph.Mark
        let watts: Double
        switch s.state {
        case .charging: mark = .bolt; watts = s.inputWatts
        case .full, .paused, .assisting: mark = .plug; watts = s.inputWatts
        case .onBattery: mark = .none; watts = -s.batteryWatts
        }
        let symbol = BatteryGlyph.key(percent: s.percent, mark: mark)
        let title = showsPower ? " " + PowerFormat.watts(watts) : ""
        // Redraw the menu bar only when what it shows changes.
        guard symbol != shownSymbol || title != shownTitle else { return }
        let symbolChanged = symbol != shownSymbol
        shownSymbol = symbol
        shownTitle = title
        if ProcessInfo.processInfo.environment["RILL_DEBUG"] != nil {
            print("menu bar \(symbol)\(title) system=\(PowerFormat.watts(s.systemWatts)) battery=\(s.batteryWatts) temp=\(s.temperature ?? -1) state=\(s.state)")
            fflush(stdout)
        }
        button.toolTip = "\(s.percent)%"
        if symbolChanged {
            button.image = BatteryGlyph.image(percent: s.percent, mark: mark)

        }
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
        )
    }

    /// Matches the popover to its content's height, measured before showing
    /// and after each update while open.
    private func fitPopover(force: Bool = false) {
        guard force || popover.isShown,
              let hosting = popover.contentViewController as? NSHostingController<PopoverView> else { return }
        // fittingSize squeezes the chart and rows to their minimum; ask
        // SwiftUI for the ideal height at the panel's fixed width instead.
        let size = hosting.sizeThatFits(in: NSSize(width: 360, height: 2000))
        guard size.height > 0, abs(size.height - popover.contentSize.height) > 0.5 || abs(size.width - popover.contentSize.width) > 0.5 else { return }
        popover.contentSize = size
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            model.popoverVisible = true
            fitPopover(force: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: L("打开 Dashboard", "Open Dashboard"), action: #selector(openDashboardFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let power = NSMenuItem(title: L("在菜单栏显示实时功率", "Show Live Power in Menu Bar"), action: #selector(toggleShowsPower), keyEquivalent: "")
        power.target = self
        power.state = showsPower ? .on : .off
        menu.addItem(power)
        let login = NSMenuItem(title: L("登录时打开", "Open at Login"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let prefs = NSMenuItem(title: L("设置…", "Settings…"), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        let update = NSMenuItem(title: L("检查更新…", "Check for Updates…"), action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        let issue = NSMenuItem(title: L("报告问题…", "Report an Issue…"), action: #selector(reportIssue(_:)), keyEquivalent: "")
        issue.target = self
        menu.addItem(issue)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("退出 Rill", "Quit Rill"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func openDashboardFromMenu() { openDashboard() }
    @objc func openSettingsFromMenu() { openSettings() }

    @objc func showPage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let page = DashboardPage(rawValue: raw) else { return }
        DashboardState.shared.page = page
        openDashboard()
    }

    @objc func quitSelectedApp(_ sender: Any?) {
        if let app = selectedApp { AppActions.confirmQuit(app) }
    }

    @objc func endBusiestProcess(_ sender: Any?) {
        if let app = selectedApp, let top = AppActions.busiestOtherProcess(app) {
            AppActions.endProcess(pid: top.pid, name: top.name)
        }
    }

    @objc func openActivityMonitor(_ sender: Any?) { AppActions.openActivityMonitor() }

    @objc func checkForUpdates(_ sender: Any?) { Updates.check() }
    @objc func reportIssue(_ sender: Any?) { Updates.reportIssue() }
    @objc func openRepoPage(_ sender: Any?) { NSWorkspace.shared.open(Release.repoPage) }

    /// The row selected on the Apps page, when that page is showing.
    private var selectedApp: AppUsage? {
        let state = DashboardState.shared
        guard dashboard?.isVisible == true, state.page == .apps, let id = state.selectedApp else { return nil }
        return model.allApps.first { $0.id == id }
    }

    @objc private func toggleShowsPower() {
        settings.showsPower.toggle()
    }

    @objc private func toggleLogin() {
        settings.setLaunchAtLogin(SMAppService.mainApp.status != .enabled)
        if let e = settings.loginError { NSLog("Rill login item: \(e)") }
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        model.popoverVisible = false
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        if closing === dashboard { model.dashboardVisible = false }
        let othersOpen = [dashboard, settingsWindow].contains { $0 != nil && $0 !== closing && $0!.isVisible }
        if !othersOpen { showInDock(false) }
    }

    func windowDidMiniaturize(_ notification: Notification) { model.dashboardVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { model.dashboardVisible = true }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(quitSelectedApp(_:)): return selectedApp.map(AppActions.canQuit) ?? false
        case #selector(endBusiestProcess(_:)): return selectedApp.flatMap(AppActions.busiestOtherProcess) != nil
        case #selector(showPage(_:)):
            item.state = (dashboard?.isVisible == true && (item.representedObject as? String) == DashboardState.shared.page.rawValue) ? .on : .off
            return true
        default: return true
        }
    }
}
