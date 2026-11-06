import AppKit
import Combine
import RillCore
import ServiceManagement
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zh, en
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return L("跟随系统", "System")
        case .zh: return "简体中文"
        case .en: return "English"
        }
    }
}

/// User settings, shared by the panel, the Dashboard, the menu and the
/// Settings window. Views key their content on `language`, so switching
/// takes effect at once without a restart.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }
    @Published var showsPower: Bool {
        didSet { UserDefaults.standard.set(showsPower, forKey: "showsPower") }
    }
    /// Mirrors SMAppService; writing registers or unregisters the login item.
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var loginError: String?

    private init() {
        // Default is Chinese, as Rill always was; this Mac's first system
        // language is en-CN, so "System" would have flipped it to English.
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .zh
        showsPower = UserDefaults.standard.object(forKey: "showsPower") as? Bool ?? true
    }

    nonisolated static var isChinese: Bool {
        switch AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .zh {
        case .zh: return true
        case .en: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Chinese or English by the current setting. Two languages only: Rill is a
/// personal tool, and inline pairs keep every string next to its use.
func L(_ zh: String, _ en: String) -> String { AppSettings.isChinese ? zh : en }

func durationText(_ minutes: Int) -> String {
    PowerFormat.duration(minutes: minutes, english: !AppSettings.isChinese)
}

/// One pane of standard grouped settings. Changes apply at once, as in
/// System Settings; there is no Save button.
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker(L("语言", "Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                Toggle(L("登录时打开", "Open at Login"), isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }))
            } header: {
                Text(L("通用", "General"))
            } footer: {
                if let e = settings.loginError {
                    Text(e).foregroundStyle(.red)
                }
            }
            Section {
                Toggle(L("显示实时功率", "Show Live Power"), isOn: $settings.showsPower)
            } header: {
                Text(L("菜单栏", "Menu Bar"))
            } footer: {
                Text(L("在电池图标旁显示充电器输入或电池放电的瓦数。", "Shows charger input or battery discharge in watts next to the battery icon."))
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .id(settings.language)
        .onAppear { settings.refreshLaunchAtLogin() }
    }
}
