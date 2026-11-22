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
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--page"), arguments.indices.contains(index + 1) { model.openSettings(page: SettingsPage(rawValue: arguments[index + 1])) }
        else if arguments.contains("--settings") { model.openSettings() }
    }
    func application(_ application: NSApplication, open urls: [URL]) { urls.forEach(model.route) }
    /// Opening the app again (Finder, Spotlight, Launchpad) shows settings — the only way in if macOS hides our icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { model.openSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { if model.main != nil { model.stop() } }
}
@main enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
