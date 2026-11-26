import AppKit
import Combine
import RillCore
import ServiceManagement
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, zh
    case zhHant = "zh-Hant"
    case ja, ko, de, fr, es
    var id: String { rawValue }
    /// Each language under its own name, as in System Settings.
    var label: String {
        switch self {
        case .system: return L("跟随系统", "System")
        case .en: return "English"
        case .zh: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        }
    }

    /// The first of the Mac's preferred languages that Rill has, else English.
    static func fromSystem(_ preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        for id in preferred {
            let l = id.lowercased()
            if l.hasPrefix("zh") {
                return l.contains("hant") || l.hasSuffix("-tw") || l.hasSuffix("-hk") || l.hasSuffix("-mo") ? .zhHant : .zh
            }
            for lang in [AppLanguage.en, .ja, .ko, .de, .fr, .es] where l.hasPrefix(lang.rawValue) { return lang }
        }
        return .en
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return L("跟随系统", "System")
        case .light: return L("浅色", "Light")
        case .dark: return L("深色", "Dark")
        }
    }
    /// nil lets every window follow the system setting.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
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
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "language")
            Self.resolved = Self.resolve(language)
        }
    }
    @Published var showsPower: Bool {
        didSet { UserDefaults.standard.set(showsPower, forKey: "showsPower") }
    }
    /// Light, dark or the system's choice; applied app-wide through NSApp.appearance.
    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }
    /// Mirrors SMAppService; writing registers or unregisters the login item.
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var loginError: String?

    private init() {
        // Default is Chinese, as Rill always was; this Mac's first system
        // language is en-CN, so "System" would have flipped it to English.
        language = Self.stored
        showsPower = UserDefaults.standard.object(forKey: "showsPower") as? Bool ?? true
        appearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
    }

    /// Sets the app-wide appearance; windows and the popover inherit it.
    func applyAppearance() {
        NSApp?.appearance = appearance.nsAppearance
    }

    /// `L()` runs for every string in every view body, so the answer is kept
    /// here rather than read from UserDefaults each time.
    nonisolated(unsafe) private static var resolved = resolve(stored)

    /// The language strings are shown in, with "System" resolved.
    nonisolated static var current: AppLanguage { resolved }
    nonisolated static var isChinese: Bool { resolved == .zh }

    nonisolated private static var stored: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .zh
    }

    nonisolated private static func resolve(_ language: AppLanguage) -> AppLanguage {
        language == .system ? AppLanguage.fromSystem() : language
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

/// A string in the current language. Simplified Chinese and English sit
/// inline next to their use; the other languages are looked up by the
/// English text in `Translations` (Localization/Translations.json, generated
/// by scripts/build-strings.py). With arguments, the chosen text is a
/// printf format; `%@` takes the interpolated values as strings.
func L(_ zh: String, _ en: String, _ args: CVarArg...) -> String {
    let format: String
    switch AppSettings.current {
    case .zh: format = zh
    case .en, .system: format = en
    case let lang: format = Translations.lookup(en, language: lang.rawValue) ?? en
    }
    return args.isEmpty ? format : String(format: format, arguments: args)
}

func durationText(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    return h > 0 ? L("%1$@ 小时 %2$@ 分", "%1$@ h %2$@ min", "\(h)", "\(m)") : L("%@ 分", "%@ min", "\(m)")
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
                Picker(L("外观", "Appearance"), selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
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
