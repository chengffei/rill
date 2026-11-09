import Foundation

/// Where Rill lives on GitHub, and the pure parts of checking for updates and
/// filing issues, kept here so they can be tested.
public enum Release {
    public static let repo = "chengffei/rill"
    public static let repoPage = URL(string: "https://github.com/\(repo)")!
    /// Redirects to the newest release's tag page; read with a HEAD request
    /// instead of the REST API, which allows 60 anonymous calls an hour per IP.
    public static let latestPage = URL(string: "https://github.com/\(repo)/releases/latest")!
    /// jsDelivr's resolver for the newest version tag; answers where github.com is slow.
    public static let jsDelivrResolver = URL(string: "https://data.jsdelivr.com/v1/packages/gh/\(repo)/resolved")!

    public static func tagPage(_ version: String) -> URL {
        URL(string: "https://github.com/\(repo)/releases/tag/v\(version)") ?? latestPage
    }

    /// Reads the version from a URL such as `…/releases/tag/v0.7.0`.
    public static func version(fromTagURL url: URL) -> String? {
        let parts = url.pathComponents
        guard parts.count >= 2, parts[parts.count - 2] == "tag" else { return nil }
        let tag = parts[parts.count - 1]
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return version.first?.isNumber == true ? version : nil
    }

    /// Reads `{"version": "0.7.0", …}` from jsDelivr's resolver.
    public static func version(fromJSDelivr data: Data) -> String? {
        struct Payload: Decodable { let version: String? }
        guard let version = (try? JSONDecoder().decode(Payload.self, from: data))?.version,
              version.first?.isNumber == true else { return nil }
        return version
    }

    /// Compares dotted numeric versions, so "0.10.0" is newer than "0.9.1".
    public static func isNewer(_ remote: String, than local: String) -> Bool {
        let parts = { (v: String) in v.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let r = parts(remote), l = parts(local)
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0, b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// A new-issue page with the environment filled in, so a report arrives
    /// with the version and machine without the reporter looking them up.
    public static func newIssueURL(appVersion: String, build: String, system: String, model: String,
                                   english: Bool) -> URL {
        let env = """
            - Rill \(appVersion) (\(build))
            - macOS \(system)
            - \(model)
            """
        let body = english
            ? "### What happened\n\n\n### Steps to reproduce\n\n\n### Expected\n\n\n### Environment\n\(env)\n"
            : "### 发生了什么\n\n\n### 复现步骤\n\n\n### 期望结果\n\n\n### 环境\n\(env)\n"
        var c = URLComponents(string: "https://github.com/\(repo)/issues/new")!
        c.queryItems = [URLQueryItem(name: "body", value: body)]
        return c.url!
    }
}
