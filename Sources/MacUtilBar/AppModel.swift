import AppKit
import SwiftUI
import ServiceManagement
import MacUtilBarCore

final class AppModel: NSObject, ObservableObject, NSMenuDelegate {
    @Published var config = Configuration()
    @Published var state: RevealState = .all
    @Published var error = ""
    @Published var shortcutFailed = false
    @Published var orderBroken = false
    @Published var geometryUnavailable = false
    @Published var hidingUnavailable = false
    @Published var notchCount = 0
    @Published var counts = [0, 0, 0]
    @Published var loginStatus = ""
    let file: ConfigurationFile
    var main: NSStatusItem!, spacer: NSStatusItem!, permanent: NSStatusItem!
    var settings: NSWindow?
    let hotkey = HotKey()
    let frames = StatusItemFrames()
    var ready = false
    var mainScreen: NSScreen? { guard let frame = frames.frame(main) else { return nil }; return NSScreen.screens.first { $0.frame.intersects(frame) } }
    var timer: Timer?
    var monitors: [Any] = []
    var suspended = false
    var hoverStart: Date?
    var collapse = AutoCollapse()
    var selfTest = HidingSelfTest()
    var expandedWindows: [BarWindow] = []
    var generation = 0
    var menuOpen = false
    var activeMenu: NSMenu?
    var menuTimer: Timer?
    var menuExit: Date?
    var observers: [NSObjectProtocol] = []
    var isEnglish: Bool { config.language == "en" || (config.language == "system" && !(Locale.preferredLanguages.first ?? "en").hasPrefix("zh")) }
    func t(_ zh: String, _ en: String) -> String { isEnglish ? en : zh }
    override init() {
        file = ConfigurationFile(url: URL(fileURLWithPath: ProcessInfo.processInfo.environment["MACUTILBAR_CONFIG"] ?? NSHomeDirectory() + "/.config/macutilbar/config.toml"))
        super.init()
    }
    func start(completion: @escaping () -> Void = {}) {
        reload()
        if !FileManager.default.fileExists(atPath: file.url.path) { do { try file.write(config) } catch { self.error = error.localizedDescription } }
        seed(); createItems(); applyConfig()
        hotkey.action = { [weak self] in self?.toggle() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.config.collapseOnSwitch else { return }; self.setState(.collapsed)
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.suspend(true) })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.suspend(false) })
        }
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.suspend(value) }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in guard let self else { return }; self.setState(self.state) })
        // Start expanded so the user can place icons; never hide unverified icons on first launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.frames.identify([self.main, self.spacer, self.permanent]) { self.ready = true; self.refresh(); if self.geometryUnavailable { self.openSettings() }; completion() }
        }
    }
    func seed(force: Bool = false) {
        for (name, position) in [("Main", 0), ("HiddenSpacer", 1), ("AlwaysHidden", 2)] {
            let key = "NSStatusItem Preferred Position MacUtilBar." + name
            if force || UserDefaults.standard.object(forKey: key) == nil { UserDefaults.standard.set(position, forKey: key) }
        }
    }
    func createItems() {
        permanent = NSStatusBar.system.statusItem(withLength: 22); permanent.autosaveName = "MacUtilBar.AlwaysHidden"
        spacer = NSStatusBar.system.statusItem(withLength: 8); spacer.autosaveName = "MacUtilBar.HiddenSpacer"
        main = NSStatusBar.system.statusItem(withLength: 26); main.autosaveName = "MacUtilBar.Main"
        main.button?.target = self; main.button?.action = #selector(click)
        main.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        main.button?.toolTip = "MacUtil Bar — ⌥ " + t("显示全部", "Show All")
        updateIcon()
    }
    func fixOrder() {
        setState(.all)
        [main, spacer, permanent].forEach { if let item = $0 { NSStatusBar.system.removeStatusItem(item) } }
        seed(force: true); createItems(); ready = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.frames.identify([self.main, self.spacer, self.permanent]) { self.ready = true; self.refresh() } }
    }
    @objc func click() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true || hidingUnavailable { showMenu(); return }
        if event?.modifierFlags.contains(.option) == true { setState(state == .all ? .collapsed : .all) } else { toggle() }
    }
    func toggle() { setState(state == .collapsed ? .revealed : .collapsed) }
    func setState(_ next: RevealState) {
        guard main != nil else { return }
        // During full-screen menu-bar suppression AppKit exposes placeholder frames.
        // Do not infer order or mutate hiding geometry until the bar is visible again.
        if next != .all {
            guard let frame = frames.frame(main), NSScreen.screens.contains(where: { $0.frame.contains(frame) }) else { return }
        }
        guard (!hidingUnavailable && !orderBroken) || next == .all else { return }
        if state == .all || state == .revealed { captureTargets() }
        let previous = state
        state = next; generation += 1; let token = generation
        collapse = AutoCollapse()
        let width = Geometry.collapseLength(widths: NSScreen.screens.map { $0.frame.width })
        spacer.length = next == .collapsed ? width : 8
        permanent.length = next == .all ? 22 : width
        updateIcon()
        if next == .collapsed && previous != .collapsed {
            let before = expandedWindows
            for delay in [0.5, 1.2] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.generation == token, let frame = self.frames.frame(self.main) else { return }
                    if self.selfTest.check(before: before, after: barWindows(), screens: NSScreen.screens.map { quartzRect($0.frame) }, main: quartzRect(frame)) == false {
                        self.hidingUnavailable = true; self.setState(.all)
                    }
                }
            }
        }
    }
    func captureTargets() {
        guard let mainFrame = frames.frame(main), let screen = mainScreen else { return }
        let own = Set([main, spacer, permanent].compactMap { frames.id($0!) })
        let screenRect = quartzRect(screen.frame)
        expandedWindows = barWindows(onScreen: true).filter { !own.contains($0.id) && $0.frame.maxX <= mainFrame.minX && screenRect.intersects($0.frame) }
    }
    func refresh() {
        guard let mf = frames.frame(main), let pf = frames.frame(permanent), let sf = frames.frame(spacer) else { return }
        guard NSScreen.screens.contains(where: { $0.frame.contains(mf) }) else { geometryUnavailable = ready; return }
        geometryUnavailable = false
        orderBroken = !Geometry.ordered(main: mf, spacer: sf, permanent: pf)
        if state == .all {
            let own = Set([main, spacer, permanent].compactMap { frames.id($0!) })
            // Counts are sampled only while all sections are expanded.
            let screen = mainScreen ?? NSScreen.main!
            let sampled = barWindows(onScreen: true).filter { !own.contains($0.id) && quartzRect(screen.frame).intersects($0.frame) }
            counts = [Section.alwaysHidden, .hidden, .visible].map { section in sampled.filter { Geometry.section(x: $0.frame.midX, main: mf.minX, permanent: pf.minX) == section }.count }
        }
        if state != .collapsed, let screen = mainScreen, let right = screen.auxiliaryTopRightArea, let left = screen.auxiliaryTopLeftArea {
            let notch = CGRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top, width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
            notchCount = Geometry.obscured(barWindows(onScreen: true), screen: quartzRect(screen.frame), notch: quartzRect(notch)).count
        } else { notchCount = 0 }
        updateIcon()
    }
    func updateIcon() {
        main?.button?.image = barIcon(expanded: state != .collapsed, badge: config.notchBadge && notchCount > 0, failed: hidingUnavailable)
        main?.button?.setAccessibilityLabel(t("MacUtil Bar，", "MacUtil Bar, ") + (state == .collapsed ? t("已收起，按下以展开", "collapsed, press to reveal") : t("已展开，按下以收起", "expanded, press to collapse")))
        permanent?.button?.title = config.divider == "line" ? "│" : config.divider == "dot" ? "·" : "‹‹"
        permanent?.button?.appearsDisabled = true
    }
    func tick() {
        reload(); refresh()
        loginStatus = String(describing: SMAppService.mainApp.status)
        guard !suspended, ready else { return }
        if collapse.tick(delay: config.autoCollapse, paused: pointerInBar() || menuOpen || menusVisible(), expanded: state != .collapsed) { setState(.collapsed) }
    }
    func reload() {
        do { let next = try file.read(); error = ""; if next != config { config = next; if main != nil { applyConfig() } } }
        catch { self.error = error.localizedDescription }
    }
    func save(_ change: (inout Configuration) -> Void) {
        var next = config; change(&next)
        do { try file.write(next); config = next; error = ""; applyConfig() } catch { self.error = error.localizedDescription }
    }
    func applyConfig() {
        shortcutFailed = !hotkey.register(config.shortcut)
        NSApp.appearance = config.appearance == "system" ? nil : NSAppearance(named: config.appearance == "dark" ? .darkAqua : .aqua)
        installMonitors(); updateIcon()
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            save { $0.launchAtLogin = enabled }
        } catch { self.error = error.localizedDescription }
        objectWillChange.send()
    }
    func suspend(_ value: Bool) { suspended = value; installMonitors() }
    func pointerInBar() -> Bool {
        guard let screen = mainScreen else { return false }
        let p = NSEvent.mouseLocation
        return p.x >= screen.frame.minX && p.x <= screen.frame.maxX && p.y <= screen.frame.maxY && p.y >= screen.frame.maxY - max(24, screen.safeAreaInsets.top)
    }
    func installMonitors() {
        monitors.forEach(NSEvent.removeMonitor); monitors = []; hoverStart = nil
        guard !suspended else { return }
        var mask: NSEvent.EventTypeMask = []
        if config.hover { mask.insert(.mouseMoved) }
        if config.scroll { mask.insert(.scrollWheel) }
        guard !mask.isEmpty else { return }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handleMouse($0) }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in self?.handleMouse(event); return event }) { monitors.append(monitor) }
    }
    func handleMouse(_ event: NSEvent) {
        guard pointerInBar(), !menuOpen else { hoverStart = nil; return }
        if event.type == .scrollWheel && abs(event.scrollingDeltaY) > 0.5 { setState(event.scrollingDeltaY < 0 ? .revealed : .collapsed); return }
        guard config.hover, state == .collapsed, let screen = mainScreen else { return }
        let p = NSEvent.mouseLocation, windows = barWindows(onScreen: true).filter { $0.frame.width < 200 }
        let q = CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - p.y)
        let leftmost = windows.filter { quartzRect(screen.frame).intersects($0.frame) }.map(\.frame.minX).min() ?? screen.frame.maxX
        // Restrict fallback to a 40pt gap adjacent to the status area, never the app-menu side.
        guard p.x >= leftmost - 40, !windows.contains(where: { $0.frame.contains(q) }), p.x > (screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX) else { hoverStart = nil; return }
        if hoverStart == nil {
            let started = Date(); hoverStart = started
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(config.hoverDelay) / 1000) { [weak self] in
                guard let self, self.hoverStart == started, self.pointerInBar(), self.isEmptyHoverSpace(), !self.suspended else { return }; self.setState(.revealed); self.hoverStart = nil
            }
        }
    }
    func isEmptyHoverSpace() -> Bool {
        guard let screen = mainScreen else { return false }
        let p = NSEvent.mouseLocation
        let windows = barWindows(onScreen: true).filter { $0.frame.width < 200 && quartzRect(screen.frame).intersects($0.frame) }
        let q = CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - p.y)
        let edge = windows.map(\.frame.minX).min() ?? screen.frame.maxX
        return p.x >= edge - 40 && p.x > (screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX) && !windows.contains { $0.frame.contains(q) }
    }
    func showMenu() {
        let menu = NSMenu(); menu.delegate = self
        if orderBroken { menu.addItem(withTitle: t("分隔符顺序异常 · 修复", "Dividers out of order · Fix"), action: #selector(repair), keyEquivalent: "") }
        if hidingUnavailable { menu.addItem(withTitle: t("当前系统无法隐藏图标", "Hiding unavailable on this system"), action: #selector(openSettings), keyEquivalent: "") }
        menu.addItem(withTitle: state == .all ? t("收起全部图标", "Hide All Icons") : t("显示全部图标", "Show All Icons"), action: #selector(all), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: t("设置…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: t("退出 MacUtil Bar", "Quit MacUtil Bar"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }; activeMenu = menu
        main.menu = menu; main.button?.performClick(nil); main.menu = nil
    }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; menuExit = nil
        menuTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            let inside = NSApp.windows.contains { $0.isVisible && $0.level.rawValue >= NSWindow.Level.popUpMenu.rawValue && $0.frame.insetBy(dx: -12, dy: -12).contains(point) }
            if inside || self.frames.frame(self.main)?.insetBy(dx: -8, dy: -8).contains(point) == true { self.menuExit = nil }
            else if let exit = self.menuExit { if Date().timeIntervalSince(exit) > 0.6 { self.activeMenu?.cancelTracking() } } else { self.menuExit = Date() }
        }
        RunLoop.main.add(menuTimer!, forMode: .common)
    }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; menuTimer?.invalidate(); menuTimer = nil; activeMenu = nil }
    @objc func repair() { fixOrder() }
    @objc func all() { setState(state == .all ? .collapsed : .all) }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func openSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "MacUtil Bar"; window.minSize = NSSize(width: 620, height: 520); window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: self)); window.center(); window.setFrameAutosaveName("Settings")
            settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    func route(_ url: URL) {
        guard let route = Route(url: url) else { return }
        switch route { case .toggle: toggle(); case .show: setState(.revealed); case .hide: setState(.collapsed); case .showAll: setState(.all); case .settings: openSettings() }
    }
    func stop() { spacer.length = 8; permanent.length = 22; monitors.forEach(NSEvent.removeMonitor); timer?.invalidate() }
}
