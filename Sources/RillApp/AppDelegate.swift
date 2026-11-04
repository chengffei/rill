import AppKit
import RillCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PowerModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        popover.behavior = .transient
        popover.animates = false
        // Light only, like the rest of Felix's tools.
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))

        model.onUpdate = { [weak self] in self?.updateStatusItem($0) }
        model.start()
        if ProcessInfo.processInfo.environment["RILL_DEBUG"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                let w = self?.statusItem.button?.window
                print("status item frame=\(w?.frame ?? .zero) visible=\(w?.isVisible ?? false) occluded=\(w.map { !$0.occlusionState.contains(.visible) } ?? true) isVisible=\(self?.statusItem.isVisible ?? false)")
                fflush(stdout)
            }
        }

        // Debug: RILL_SNAPSHOT=/path.png renders the panel after a few samples and quits.
        if let path = ProcessInfo.processInfo.environment["RILL_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [model] in
                let renderer = ImageRenderer(content: PopoverView(model: model).environment(\.colorScheme, .light))
                renderer.scale = 2
                if let cg = renderer.cgImage {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
        }
    }

    private func updateStatusItem(_ s: PowerSnapshot?) {
        guard let button = statusItem.button else { return }
        guard let s else {
            button.image = NSImage(systemSymbolName: "bolt.slash", accessibilityDescription: nil)
            button.title = ""
            return
        }
        let symbol: String
        let watts: Double
        switch s.state {
        case .charging: symbol = "bolt.fill"; watts = s.inputWatts
        case .full, .paused: symbol = "powerplug.fill"; watts = s.inputWatts
        case .onBattery: symbol = "battery.75percent"; watts = -s.batteryWatts
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        image?.isTemplate = true
        button.image = image
        button.attributedTitle = NSAttributedString(
            string: " " + PowerFormat.watts(watts),
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
        )
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
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
