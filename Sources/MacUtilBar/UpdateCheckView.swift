import AppKit
import SwiftUI
import MacUtilBarCore

@MainActor final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle, checking, current, failed
        case available(UpdateManifest), unsupported(UpdateManifest)
    }
    @Published private(set) var state: State = .idle
    @Published private(set) var checkedAt: Date?
    let product: String
    let bundleIdentifier: String
    let currentVersion: String
    let currentBuild: Int
    let system: OperatingSystemVersion
    private let fetch: (URL) async throws -> Data

    init(product: String = "MacUtilBar", bundleIdentifier: String = "local.macutilbar.app",
         currentVersion: String = "1.0.2", currentBuild: Int = 3,
         system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
         fetch: @escaping (URL) async throws -> Data = UpdateChecker.download) {
        self.product = product; self.bundleIdentifier = bundleIdentifier
        self.currentVersion = currentVersion; self.currentBuild = currentBuild
        self.system = system; self.fetch = fetch
    }

    func check() async {
        guard state != .checking else { return }
        state = .checking
        do {
            let url = URL(string: "https://raw.githubusercontent.com/\(UpdateManifest.repository)/main/feeds/\(product).json")!
            let data = try await fetch(url)
            try Task.checkCancellation()
            let manifest = try UpdateManifest.decode(data, product: product, bundleIdentifier: bundleIdentifier)
            checkedAt = Date()
            if !manifest.isNewer(than: currentBuild) { state = .current }
            else { state = manifest.supports(system) ? .available(manifest) : .unsupported(manifest) }
        } catch { state = .failed }
    }

    nonisolated static func download(_ url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url == url, response.expectedContentLength <= UpdateManifest.maximumBytes else {
            throw UpdateManifest.Failure.unavailable
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < UpdateManifest.maximumBytes else { throw UpdateManifest.Failure.invalidManifest }
            data.append(byte)
        }
        return data
    }
}

struct UpdateCheckView: View {
    let english: Bool
    @StateObject private var checker = UpdateChecker()
    private func t(_ zh: String, _ en: String) -> String { english ? en : zh }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(t("软件更新", "Software Update")).font(.headline)
                Spacer()
                Text("v\(checker.currentVersion) (\(checker.currentBuild))").font(.caption).foregroundStyle(.secondary)
                Button(t("检查更新…", "Check for Updates…")) { Task { await checker.check() } }
                    .disabled(checker.state == .checking).accessibilityIdentifier("updates.check")
            }
            Text(t("点击后连接 GitHub 检查版本；发现新版后打开发布页，下载 PKG 手动安装。", "Check GitHub on request, then open the release page to download and manually install the PKG."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            switch checker.state {
            case .idle: EmptyView()
            case .checking: Text(t("正在检查…", "Checking…"))
            case .current: Text(t("已是最新发布版本。", "You have the latest published version."))
            case .failed: Text(t("暂时无法检查更新，请检查网络后重试。", "Could not check for updates. Check your connection and try again.")).foregroundStyle(.orange)
            case .available(let release):
                HStack {
                    Text(t("发现新版本 ", "New version ") + release.version)
                    Link(t("查看更新并下载 PKG", "View Release and Download PKG"), destination: release.releaseURL)
                        .accessibilityIdentifier("updates.download")
                }
            case .unsupported(let release):
                Text(t("新版 \(release.version) 需要 macOS \(release.minimumSystemVersion) 或更高版本。", "Version \(release.version) requires macOS \(release.minimumSystemVersion) or later.")).foregroundStyle(.secondary)
            }
            if let date = checker.checkedAt {
                Text(t("上次成功检查：", "Last successful check: ") + date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("updates.section")
    }
}
