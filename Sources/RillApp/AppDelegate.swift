import AppKit
import RillCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PowerModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var dashboard: NSWindow?
    private var shownSymbol = ""
    private var shownTitle = ""

    /// Launching Rill again (Finder, Spotlight) opens the Dashboard; there is no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openDashboard()
        return false
    }

    func openDashboard() {
        if dashboard == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 860),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Rill"
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.appearance = NSAppearance(named: .aqua)
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: DashboardView(model: model))
            w.setContentSize(NSSize(width: 1040, height: 860))
            w.center()
            w.setFrameAutosaveName("RillDashboard")
            w.delegate = self
            dashboard = w
        }
        model.dashboardVisible = true
        NSApp.activate(ignoringOtherApps: true)
        dashboard?.makeKeyAndOrderFront(nil)
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
        // Light only, like the rest of Felix's tools.
        popover.appearance = NSAppearance(named: .aqua)
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

        // Debug: RILL_SNAPSHOT=/path.png renders the panel (RILL_SNAPSHOT_DASHBOARD=1 the
        // Dashboard) after a few samples and quits.
        if let path = ProcessInfo.processInfo.environment["RILL_SNAPSHOT"] {
            let dash = ProcessInfo.processInfo.environment["RILL_SNAPSHOT_DASHBOARD"] != nil
            model.popoverVisible = true
            model.dashboardVisible = dash
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [model] in
                let content = dash
                    ? AnyView(DashboardView(model: model, scrolls: false).frame(width: 1040))
                    : AnyView(PopoverView(model: model, onOpenDashboard: {}))
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

    private var showsPower: Bool {
        get { UserDefaults.standard.object(forKey: "showsPower") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showsPower") }
    }
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
        let open = NSMenuItem(title: "打开 Dashboard", action: #selector(openDashboardFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let power = NSMenuItem(title: "在菜单栏显示实时功率", action: #selector(toggleShowsPower), keyEquivalent: "")
        power.target = self
        power.state = showsPower ? .on : .off
        menu.addItem(power)
        let login = NSMenuItem(title: "开机启动", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Rill", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openDashboardFromMenu() { openDashboard() }

    @objc private func toggleShowsPower() {
        showsPower.toggle()
        shownTitle = "\u{0}"
        updateStatusItem(lastSnapshot)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Rill login item: \(error)")
        }
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        model.popoverVisible = false
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === dashboard { model.dashboardVisible = false }
    }

    func windowDidMiniaturize(_ notification: Notification) { model.dashboardVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { model.dashboardVisible = true }
}
