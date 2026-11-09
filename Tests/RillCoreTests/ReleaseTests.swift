import XCTest
@testable import RillCore

final class ReleaseTests: XCTestCase {
    func testVersionOrder() {
        XCTAssertTrue(Release.isNewer("0.10.0", than: "0.9.1"))
        XCTAssertTrue(Release.isNewer("0.7.1", than: "0.7"))
        XCTAssertFalse(Release.isNewer("0.7.0", than: "0.7"))
        XCTAssertFalse(Release.isNewer("0.6.9", than: "0.7.0"))
    }

    func testTagURL() {
        XCTAssertEqual(Release.version(fromTagURL: URL(string: "https://github.com/chengffei/rill/releases/tag/v0.7.0")!), "0.7.0")
        XCTAssertNil(Release.version(fromTagURL: URL(string: "https://github.com/chengffei/rill/releases")!))
        XCTAssertNil(Release.version(fromTagURL: URL(string: "https://github.com/chengffei/rill/releases/tag/nightly")!))
    }

    func testJSDelivr() {
        XCTAssertEqual(Release.version(fromJSDelivr: Data(#"{"version":"0.7.0","links":{}}"#.utf8)), "0.7.0")
        XCTAssertNil(Release.version(fromJSDelivr: Data(#"{"version":null}"#.utf8)))
    }

    func testIssueURLCarriesEnvironment() {
        let url = Release.newIssueURL(appVersion: "0.7.0", build: "2", system: "27.2", model: "Mac16,1", english: true)
        let body = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value ?? ""
        XCTAssertTrue(url.absoluteString.hasPrefix("https://github.com/chengffei/rill/issues/new?"))
        XCTAssertTrue(body.contains("Rill 0.7.0 (2)"))
        XCTAssertTrue(body.contains("macOS 27.2"))
        XCTAssertTrue(body.contains("Mac16,1"))
    }
}
