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

final class CalibrationTests: XCTestCase {
    private func window(_ id: UInt32, _ width: Double) -> BarWindow { BarWindow(id: id, frame: CGRect(x: 100, y: 0, width: width, height: 33)) }
    func testRequiresRestoredWidthAndStableIdentity() {
        let before = [window(1, 42)], expanded = [window(1, 53)]
        XCTAssertEqual(StatusWindowCalibration.identify(before: before, expanded: expanded, restored: before, delta: 11), 1)
        XCTAssertNil(StatusWindowCalibration.identify(before: before, expanded: expanded, restored: expanded, delta: 11))
        XCTAssertNil(StatusWindowCalibration.identify(before: before, expanded: expanded, restored: [window(2, 42)], delta: 11))
        XCTAssertNil(StatusWindowCalibration.identify(before: before, expanded: expanded, restored: [], delta: 11))
    }
    func testAmbiguousChangesAreRejected() {
        let before = [window(1, 42), window(2, 22)]
        let expanded = [window(1, 53), window(2, 33)]
        XCTAssertNil(StatusWindowCalibration.identify(before: before, expanded: expanded, restored: before, delta: 11))
    }
}

final class PartialHidingTests: XCTestCase {
    func testPartialHidingReportsRemainderWithoutClaimingCompleteHiding() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let main = CGRect(x: 900, y: 0, width: 26, height: 24)
        let icon = BarWindow(id: 1, frame: CGRect(x: 500, y: 0, width: 30, height: 24))
        let indicator = BarWindow(id: 2, frame: CGRect(x: 400, y: 0, width: 48, height: 24))
        let relocated = BarWindow(id: 2, frame: CGRect(x: 852, y: 0, width: 48, height: 24))
        var check = HidingSelfTest()
        XCTAssertEqual(check.check(before: [icon, indicator], after: [relocated], screens: [screen], main: main), true)
        XCTAssertEqual(check.visibleRemainder, 1)
        XCTAssertEqual(check.failures, 0)
        XCTAssertEqual(check.check(before: [icon], after: [icon], screens: [screen], main: main), true)
        XCTAssertEqual(check.check(before: [icon], after: [icon], screens: [screen], main: main), false)
    }
}
