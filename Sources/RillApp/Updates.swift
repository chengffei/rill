import AppKit
import RillCore

/// "Check for Updates…" and "Report an Issue…". The update check is manual and
/// is the only time Rill goes online. Two sources are asked at once and the
/// newest answer wins: github.com's latest-release redirect, and jsDelivr,
/// which still answers on networks where github.com is slow.
@MainActor
enum Updates {
    private static var checking = false
    nonisolated private static let timeout: TimeInterval = 12

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func check() {
        guard !checking else { return }
        checking = true
        Task {
            let result = await latestVersion()
            checking = false
            present(result)
        }
    }

    static func reportIssue() {
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let url = Release.newIssueURL(
            appVersion: currentVersion,
            build: info?["CFBundleVersion"] as? String ?? "?",
            system: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            model: hardwareModel(),
            english: !AppSettings.isChinese)
        NSWorkspace.shared.open(url)
    }

    private static func latestVersion() async -> Result<String, Error> {
        let current = currentVersion
        return await withTaskGroup(of: Result<String, Error>.self) { group in
            group.addTask { await fromGitHub() }
            group.addTask { await fromJSDelivr() }
            var versions: [String] = []
            var firstError: Error?
            for await result in group {
                switch result {
                case .success(let v):
                    versions.append(v)
                    // A newer version needs no second opinion.
                    if Release.isNewer(v, than: current) {
                        group.cancelAll()
                        return .success(v)
                    }
                case .failure(let e):
                    firstError = firstError ?? e
                }
            }
            if let newest = versions.max(by: { Release.isNewer($1, than: $0) }) { return .success(newest) }
            return .failure(firstError ?? URLError(.badServerResponse))
        }
    }

    nonisolated private static func fromGitHub() async -> Result<String, Error> {
        var req = URLRequest(url: Release.latestPage, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let url = http.url, let v = Release.version(fromTagURL: url) {
                return .success(v)
            }
            return .failure(URLError(.badServerResponse))
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func fromJSDelivr() async -> Result<String, Error> {
        let req = URLRequest(url: Release.jsDelivrResolver, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if (response as? HTTPURLResponse)?.statusCode == 200, let v = Release.version(fromJSDelivr: data) {
                return .success(v)
            }
            return .failure(URLError(.badServerResponse))
        } catch {
            return .failure(error)
        }
    }

    private static func present(_ result: Result<String, Error>) {
        NSApp.activate()
        let alert = NSAlert()
        let current = currentVersion
        switch result {
        case .success(let v) where Release.isNewer(v, than: current):
            alert.messageText = L("Rill \(v) 已发布", "Rill \(v) is available")
            alert.informativeText = L("你在用 \(current)。下载后替换「应用程序」里的 Rill 即可。",
                                      "You have \(current). Download it and replace Rill in Applications.")
            alert.addButton(withTitle: L("前往下载", "Download"))
            alert.addButton(withTitle: L("以后再说", "Later"))
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(Release.tagPage(v)) }
        case .success:
            alert.messageText = L("已是最新版本", "Rill is up to date")
            alert.informativeText = L("你在用 \(current)。", "You have \(current).")
            alert.runModal()
        case .failure(let error):
            alert.alertStyle = .warning
            alert.messageText = L("无法检查更新", "Couldn't check for updates")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L("打开发布页", "Open Releases Page"))
            alert.addButton(withTitle: L("好", "OK"))
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(Release.latestPage) }
        }
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        let model = String(cString: buf)
        var cpuSize = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &cpuSize, nil, 0)
        var cpu = [CChar](repeating: 0, count: max(cpuSize, 1))
        sysctlbyname("machdep.cpu.brand_string", &cpu, &cpuSize, nil, 0)
        let chip = String(cString: cpu)
        return chip.isEmpty ? model : "\(model), \(chip)"
    }
}
