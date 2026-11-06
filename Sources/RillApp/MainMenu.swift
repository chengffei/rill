import AppKit

/// The menu bar shown while a Rill window is open. Every toolbar and
/// context-menu action is also here (Apple HIG: the toolbar can't be the
/// only place for a command); shortcuts follow the system and Activity
/// Monitor (⌘, Settings, ⌥⌘Q Quit Process).
@MainActor
enum MainMenu {
    static func build(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        let app = submenu(main, "Rill")
        app.addItem(item(L("关于 Rill", "About Rill"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        app.addItem(.separator())
        app.addItem(item(L("设置…", "Settings…"), #selector(AppDelegate.openSettingsFromMenu), ",", target: target))
        app.addItem(.separator())
        app.addItem(item(L("隐藏 Rill", "Hide Rill"), #selector(NSApplication.hide(_:)), "h"))
        let others = item(L("隐藏其他", "Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(others)
        app.addItem(item(L("全部显示", "Show All"), #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item(L("退出 Rill", "Quit Rill"), #selector(NSApplication.terminate(_:)), "q"))

        let file = submenu(main, L("文件", "File"))
        file.addItem(item(L("关闭窗口", "Close Window"), #selector(NSWindow.performClose(_:)), "w"))

        let view = submenu(main, L("显示", "View"))
        for (i, page) in DashboardPage.allCases.enumerated() {
            let it = item(page.title, #selector(AppDelegate.showPage(_:)), "\(i + 1)", target: target)
            it.representedObject = page.rawValue
            view.addItem(it)
        }
        view.addItem(.separator())
        let sidebar = item(L("显示或隐藏边栏", "Toggle Sidebar"), #selector(NSSplitViewController.toggleSidebar(_:)), "s")
        sidebar.keyEquivalentModifierMask = [.command, .control]
        view.addItem(sidebar)
        let full = item(L("进入全屏幕", "Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)), "f")
        full.keyEquivalentModifierMask = [.command, .control]
        view.addItem(full)

        let process = submenu(main, L("进程", "Process"))
        let quit = item(L("退出所选应用…", "Quit Selected App…"), #selector(AppDelegate.quitSelectedApp(_:)), "q", target: target)
        quit.keyEquivalentModifierMask = [.command, .option]
        process.addItem(quit)
        process.addItem(item(L("结束最忙的进程…", "End Busiest Process…"), #selector(AppDelegate.endBusiestProcess(_:)), target: target))
        process.addItem(.separator())
        process.addItem(item(L("打开活动监视器", "Open Activity Monitor"), #selector(AppDelegate.openActivityMonitor(_:)), target: target))

        let window = submenu(main, L("窗口", "Window"))
        window.addItem(item(L("最小化", "Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item(L("缩放", "Zoom"), #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(item(L("前置全部窗口", "Bring All to Front"), #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = window

        return main
    }

    private static func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        holder.submenu = menu
        main.addItem(holder)
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = target
        return it
    }
}
