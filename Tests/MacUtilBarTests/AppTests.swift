import XCTest
import AppKit
@testable import MacUtilBar
import MacUtilBarCore
final class AppTests: XCTestCase {
    func testRoutes() {
        for route in Route.allCases { XCTAssertEqual(Route(url: URL(string: "macutilbar://" + route.rawValue)!), route) }
        XCTAssertNil(Route(url: URL(string: "https://show")!))
        XCTAssertNil(Route(url: URL(string: "macutilbar://unknown")!))
    }
    func testShortcuts() {
        XCTAssertNotNil(Shortcut.parse("ctrl+option+b"))
        XCTAssertNil(Shortcut.parse("b")); XCTAssertNil(Shortcut.parse("ctrl+ctrl+b")); XCTAssertNil(Shortcut.parse("ctrl+escape"))
    }
    func testVersionAndPrivacyManifest() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, Version.current)
        XCTAssertEqual(plist["CFBundleVersion"] as? String, Version.build)
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "local.macutilbar.app")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
    }
    func testTemplateIcon() { let image = barIcon(expanded: true, badge: false, failed: false); XCTAssertTrue(image.isTemplate); XCTAssertEqual(image.size.width, 18) }
    func testLaunchShowsSettingsOnlyForManualLaunches() {
        XCTAssertTrue(LaunchPolicy.showsSettings(arguments: ["MacUtilBar"], loginLaunch: false, defaultLaunch: true))
        XCTAssertFalse(LaunchPolicy.showsSettings(arguments: ["MacUtilBar"], loginLaunch: true, defaultLaunch: true))
        XCTAssertFalse(LaunchPolicy.showsSettings(arguments: ["MacUtilBar"], loginLaunch: false, defaultLaunch: false))
        XCTAssertFalse(LaunchPolicy.showsSettings(arguments: ["MacUtilBar", "--background"], loginLaunch: false, defaultLaunch: true))
        XCTAssertFalse(LaunchPolicy.showsSettings(arguments: ["MacUtilBar", "--diagnose", "/tmp/x"], loginLaunch: false, defaultLaunch: true))
        XCTAssertTrue(LaunchPolicy.showsSettings(arguments: ["MacUtilBar", "--settings"], loginLaunch: true, defaultLaunch: true))
    }
}
