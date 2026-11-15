import AppKit
import MacUtilBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "local.macutilbar.app").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        model.start { [self] in
        if let index = CommandLine.arguments.firstIndex(of: "--diagnose"), CommandLine.arguments.count > index + 1 { model.diagnose(to: CommandLine.arguments[index + 1]) }
        }
        if CommandLine.arguments.contains("--settings") { model.openSettings() }
    }
    func application(_ application: NSApplication, open urls: [URL]) { urls.forEach(model.route) }
    func applicationWillTerminate(_ notification: Notification) { if model.main != nil { model.stop() } }
}
@main enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
