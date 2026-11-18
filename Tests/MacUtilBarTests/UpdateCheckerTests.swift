import XCTest
import MacUtilBarCore
@testable import MacUtilBar

final class UpdateCheckerTests: XCTestCase {
    @MainActor func testUpdaterIdentityMatchesShippedPlist() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let checker = UpdateChecker()
        XCTAssertEqual(checker.product, plist["CFBundleExecutable"] as? String)
        XCTAssertEqual(checker.bundleIdentifier, plist["CFBundleIdentifier"] as? String)
        XCTAssertEqual(checker.currentVersion, plist["CFBundleShortVersionString"] as? String)
        XCTAssertEqual(String(checker.currentBuild), plist["CFBundleVersion"] as? String)
    }

    func manifest(build: Int = 12, version: String = "1.10.0", minimum: String = "14.0.0", product: String = "MacUtilBar", url: String? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "product": product,
            "bundleIdentifier": "local.macutilbar.app", "version": version, "build": build,
            "minimumSystemVersion": minimum,
            "releaseURL": url ?? "https://github.com/PanggNOTlovebean/MacUtils-Releases/releases/tag/MacUtilBar-v\(version)"])
    }
    @MainActor func testNewCurrentOlderAndUnsupportedReleases() async throws {
        for (remote, minimum) in [(12,"14.0.0"),(10,"14.0.0"),(9,"14.0.0"),(12,"99.0.0")] {
            let data = try manifest(build: remote, minimum: minimum)
            let checker = UpdateChecker(currentBuild: 10, system: .init(majorVersion: 14, minorVersion: 0, patchVersion: 0)) { url in
                XCTAssertEqual(url.absoluteString, "https://raw.githubusercontent.com/PanggNOTlovebean/MacUtils-Releases/main/feeds/MacUtilBar.json")
                return data
            }
            XCTAssertEqual(checker.state, .idle)
            await checker.check()
            XCTAssertNotNil(checker.checkedAt)
            let release = try UpdateManifest.decode(data, product: "MacUtilBar", bundleIdentifier: "local.macutilbar.app")
            XCTAssertEqual(checker.state, remote <= 10 ? .current : (minimum == "99.0.0" ? .unsupported(release) : .available(release)))
        }
    }
    func testRejectsWrongProductMalformedVersionsAndUnsafeLinks() throws {
        for data in [try manifest(product: "AnotherApp"), try manifest(version: "1.2"), try manifest(version: "1.02.3"),
                     try manifest(build: 0), try manifest(minimum: "invalid"),
                     try manifest(url: "file:///Applications/Test.app"),
                     try manifest(url: "https://github.com.evil.test/PanggNOTlovebean/MacUtils-Releases"),
                     try manifest(url: "https://github.com/Someone/Other/releases/tag/v1"),
                     Data(repeating: 32, count: UpdateManifest.maximumBytes + 1), Data("not json".utf8)] {
            XCTAssertThrowsError(try UpdateManifest.decode(data, product: "MacUtilBar", bundleIdentifier: "local.macutilbar.app"))
        }
        XCTAssertThrowsError(try UpdateManifest.decode(manifest(), product: "MacUtilBar", bundleIdentifier: "wrong.id"))
    }
    @MainActor func testNetworkFailureCanBeRetriedWithoutStaleDownload() async throws {
        let data = try manifest()
        var fail = true
        let checker = UpdateChecker(currentBuild: 1) { _ in
            if fail { throw URLError(.notConnectedToInternet) }; return data
        }
        await checker.check(); XCTAssertEqual(checker.state, .failed)
        XCTAssertNil(checker.checkedAt)
        fail = false
        await checker.check()
        guard case .available = checker.state else { return XCTFail("Retry must recover") }
        fail = true
        await checker.check(); XCTAssertEqual(checker.state, .failed)
    }
    @MainActor func testConcurrentChecksAreCoalesced() async throws {
        let data = try manifest()
        var calls = 0
        let checker = UpdateChecker { _ in
            calls += 1
            try await Task.sleep(nanoseconds: 20_000_000)
            return data
        }
        async let first: Void = checker.check()
        async let second: Void = checker.check()
        _ = await (first, second)
        XCTAssertEqual(calls, 1)
    }
}
