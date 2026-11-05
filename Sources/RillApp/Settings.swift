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

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker(L("语言", "Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                Toggle(L("开机启动", "Launch at Login"), isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }))
                if let e = settings.loginError {
                    Text(e).font(.caption).foregroundStyle(.red)
                }
                Toggle(L("在菜单栏显示实时功率", "Show Live Power in Menu Bar"), isOn: $settings.showsPower)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .scrollIndicators(.never)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .id(settings.language)
        .onAppear { settings.refreshLaunchAtLogin() }
    }
}
