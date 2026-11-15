import XCTest
@testable import MacUtilBarCore
final class CoreTests: XCTestCase {
    func testConfigurationRoundTripAndValidation() throws {
        var c = Configuration(); c.hover = true; c.language = "en"; c.autoCollapse = 30
        XCTAssertEqual(try Configuration(toml: c.toml), c)
        for text in ["[reveal]\nhover = maybe", "[reveal]\nauto_collapse_seconds = -1", "[core]\nlanguage = \"bad\"", "[core]\nappearance = \"light\"\nappearance = \"dark\"", "[oops]\nx = true"] {
            XCTAssertThrowsError(try Configuration(toml: text))
        }
    }
    func testFileConflictPreservesExternalData() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = ConfigurationFile(url: url)
        _ = try file.read(); try file.write(Configuration())
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try file.read())
        XCTAssertThrowsError(try file.write(Configuration()))
        XCTAssertEqual(try String(contentsOf: url), "broken")
    }
    func testSectionsAndScreens() {
        XCTAssertEqual(Geometry.section(x: 200, main: 150, permanent: 50), .visible)
        XCTAssertEqual(Geometry.section(x: 100, main: 150, permanent: 50), .hidden)
        XCTAssertEqual(Geometry.section(x: 20, main: 150, permanent: 50), .alwaysHidden)
        XCTAssertEqual(Geometry.collapseLength(widths: [1470, 2560]), 2760)
        XCTAssertEqual(Geometry.collapseLength(widths: [20000]), 10000)
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let window = BarWindow(id: 1, frame: CGRect(x: 700, y: 0, width: 30, height: 33))
        XCTAssertTrue(Geometry.obscured([window], screen: screen, notch: nil).isEmpty)
        XCTAssertEqual(Geometry.obscured([window], screen: screen, notch: CGRect(x: 646, y: 0, width: 179, height: 33)).count, 1)
        XCTAssertTrue(Geometry.obscured([window], screen: screen.offsetBy(dx: 2000, dy: 1000), notch: CGRect(x: 2646, y: 1000, width: 179, height: 33)).isEmpty)
    }
    func testSelfTestRequiresActualFramesAndTwoFailures() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let main = CGRect(x: 900, y: 0, width: 26, height: 24)
        let item = BarWindow(id: 1, frame: CGRect(x: 500, y: 0, width: 30, height: 24))
        var test = HidingSelfTest()
        XCTAssertNil(test.check(before: [], after: [], screens: [screen], main: main))
        XCTAssertEqual(test.check(before: [item], after: [item], screens: [screen], main: main), true)
        XCTAssertEqual(test.check(before: [item], after: [item], screens: [screen], main: main), false)
        XCTAssertEqual(test.check(before: [item], after: [], screens: [screen], main: main), true)
        XCTAssertEqual(test.failures, 0)
        XCTAssertEqual(test.check(before: [item], after: [], screens: [screen], main: main.offsetBy(dx: -2000, dy: 0)), true)
        XCTAssertEqual(test.check(before: [item], after: [], screens: [screen], main: main.offsetBy(dx: -2000, dy: 0)), false)
    }
    func testAutoCollapsePausesAndRestarts() {
        var timer = AutoCollapse()
        XCTAssertFalse(timer.tick(delay: 2, paused: false, expanded: true))
        XCTAssertFalse(timer.tick(delay: 2, paused: true, expanded: true))
        XCTAssertFalse(timer.tick(delay: 2, paused: false, expanded: true))
        XCTAssertTrue(timer.tick(delay: 2, paused: false, expanded: true))
        XCTAssertFalse(timer.tick(delay: 0, paused: false, expanded: true))
    }
}
