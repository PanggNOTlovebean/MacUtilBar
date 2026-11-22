import AppKit
import SwiftUI
import ServiceManagement
import MacUtilBarCore

enum LoginState { case off, on, needsApproval, unavailable }

final class AppModel: NSObject, ObservableObject, NSMenuDelegate, NSWindowDelegate {
    @Published var config = Configuration()
    @Published var state: RevealState = .all
    @Published var error = ""
    @Published var shortcutFailed = false
    @Published var searchShortcutFailed = false
    @Published var orderBroken = false
    @Published var geometryUnavailable = false
    @Published var hidingUnavailable = false
    @Published var visibleRemainder = 0
    @Published var notchCount = 0
    @Published var counts = [0, 0, 0]
    @Published var hasCountSample = false
    @Published var ready = false
    @Published var loginState: LoginState = .off
    @Published var loginBusy = false
    @Published var loginError: String?
    @Published var axTrusted = Accessibility.trusted
    /// What the settings list and search show. Republished only when an icon appears,
    /// disappears, is renamed or changes section/order — not when a live icon's width changes.
    @Published var layout: [BarSection: [MenuBarItem]] = [.visible: [], .hidden: [], .alwaysHidden: []]
    /// Always-fresh scan results for moves and presses (not published).
    var liveItems: [MenuBarItem] = []
    /// Diagnostic only: populate the icon list from window-server frames without Accessibility.
    let demoItems = CommandLine.arguments.contains("--demo-items")
    var accessibilityTrusted: Bool { demoItems || Accessibility.trusted }
    /// Diagnostic only: log every published change and status item write.
    let traceUpdates = CommandLine.arguments.contains("--trace-updates")
    private var iconKey = ""
    @Published var itemsLoaded = false
    @Published var moving: String?
    @Published var moveErrors: [String: String] = [:]
    @Published var page: SettingsPage = .icons
    @Published var spacing: Int? = SystemSpacing.current
    /// The shortcut field currently recording; global hotkeys stay unregistered meanwhile.
    @Published var recordingSlot: HotKeys.Slot?
    let file: ConfigurationFile
    var main: NSStatusItem!, spacer: NSStatusItem!, permanent: NSStatusItem!
    var settings: NSWindow?
    let hotkeys = HotKeys()
    let frames = StatusItemFrames()
    let identifier = ItemIdentifier()
    var records: [String: AXItemRecord] = [:]
    lazy var search = SearchPanelController(model: self)
    var itemConsumers = 0
    var mainScreen: NSScreen? { guard let frame = frames.frame(main) else { return nil }; return NSScreen.screens.first { $0.frame.intersects(frame) } }
    var timer: Timer?
    var ticks = 0
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
    var hasNotch: Bool { NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } }
    /// Window-server frames of our three items, when all are verified.
    var dividers: Dividers? {
        guard let main, let spacer, let permanent, let m = frames.frame(main), let s = frames.frame(spacer), let p = frames.frame(permanent) else { return nil }
        return Dividers(main: quartzRect(m), spacer: quartzRect(s), permanent: quartzRect(p))
    }
    var grouped: [BarSection: [MenuBarItem]] {
        layout
    }
    /// Counts per section: identified icons when Accessibility is on, else window samples.
    var sectionCounts: [BarSection: Int]? {
        if axTrusted && itemsLoaded && dividers != nil { return grouped.mapValues(\.count) }
        guard hasCountSample && !geometryUnavailable else { return nil }
        return [.alwaysHidden: counts[0], .hidden: counts[1], .visible: counts[2]]
    }

    func demoRecords() -> [AXItemRecord] {
        let own = Set([main, spacer, permanent].compactMap { $0.flatMap(frames.id) })
        return barWindows().filter { !own.contains($0.id) && $0.frame.width < 300 }.enumerated().map { index, window in
            AXItemRecord(item: MenuBarItem(id: "demo#\(window.id)", bundleID: "local.demo.\(index)", appName: "Demo \(window.id)", label: "", pid: 1, frame: window.frame),
                         element: AXUIElementCreateApplication(0))
        }
    }
    override init() {
        file = ConfigurationFile(url: URL(fileURLWithPath: ProcessInfo.processInfo.environment["MACUTILBAR_CONFIG"] ?? NSHomeDirectory() + "/.config/macutilbar/config.toml"))
        super.init()
    }
    func start(completion: @escaping () -> Void = {}) {
        reload()
        if !FileManager.default.fileExists(atPath: file.url.path) { do { try file.write(config) } catch { self.error = error.localizedDescription } }
        seed(); createItems(); applyConfig(); refreshLogin()
        hotkeys.actions = [.toggle: { [weak self] in self?.toggle() }, .search: { [weak self] in self?.search.toggle() }]
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.config.collapseOnSwitch, self.moving == nil,
                  (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.setState(.collapsed)
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
        // Preferred positions are distances from the right edge: main and spacer start
        // at the right, ‹‹ at the far left, so existing icons begin in “Hidden”.
        let far = Int(NSScreen.screens.map(\.frame.width).max() ?? 3000)
        for (name, position) in [("Main", 0), ("HiddenSpacer", 1), ("AlwaysHidden", far)] {
            let key = "NSStatusItem Preferred Position MacUtilBar." + name
            if force || UserDefaults.standard.object(forKey: key) == nil { UserDefaults.standard.set(position, forKey: key) }
        }
    }
    func createItems() {
        permanent = NSStatusBar.system.statusItem(withLength: 22)
        spacer = NSStatusBar.system.statusItem(withLength: 8)
        main = NSStatusBar.system.statusItem(withLength: 26)
        // Let AppKit attach the items before restoring their saved positions.
        for (name, item) in [("AlwaysHidden", permanent!), ("HiddenSpacer", spacer!), ("Main", main!)] {
            DispatchQueue.main.async { item.autosaveName = "MacUtilBar." + name }
        }
        main.button?.target = self; main.button?.action = #selector(click)
        main.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        main.button?.toolTip = "MacUtil Bar — ⌥ " + t("显示全部", "Show All")
        updateIcon()
    }
    func retryGeometry() {
        guard ready else { return }
        ready = false
        frames.identify([main, spacer, permanent]) { self.ready = true; self.refresh() }
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
    /// Whether a state can be applied now (used to enable controls).
    func canApply(_ next: RevealState) -> Bool {
        guard main != nil, ready, moving == nil else { return false }
        if next == .all { return true }
        return !geometryUnavailable && !hidingUnavailable && !orderBroken
    }
    func setState(_ next: RevealState) {
        guard main != nil, ready else { return }
        // A ⌘-drag in progress needs every icon on screen; hotkeys, clicks and URLs must not collapse mid-move.
        guard moving == nil || next == .all else { return }
        // During full-screen menu-bar suppression AppKit exposes placeholder frames.
        // Do not infer order or mutate hiding geometry until the bar is visible again.
        if next != .all {
            guard let frame = frames.frame(main), NSScreen.screens.contains(where: { $0.frame.contains(frame) }) else { return }
        }
        guard (!hidingUnavailable && !orderBroken) || next == .all else { return }
        if state == .all || state == .revealed { captureTargets() }
        let previous = state
        if next != .collapsed { visibleRemainder = 0 }
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
                    let after = barWindows()
                    if CommandLine.arguments.contains("--diagnose") {
                        print("hiding check", "main", frame, "targets", before.map { "\($0.id):\($0.frame)" }, "after", after.filter { w in before.contains { $0.id == w.id } }.map { "\($0.id):\($0.frame)" })
                    }
                    let available = self.selfTest.check(before: before, after: after, screens: NSScreen.screens.map { quartzRect($0.frame) }, main: quartzRect(frame))
                    self.visibleRemainder = self.selfTest.visibleRemainder
                    if available == false {
                        self.hidingUnavailable = true; self.setState(.all)
                    }
                }
            }
        }
    }
    func captureTargets() {
        guard let spacerFrame = frames.frame(spacer), let screen = mainScreen else { return }
        let own = Set([main, spacer, permanent].compactMap { frames.id($0!) })
        let screenRect = quartzRect(screen.frame), edge = quartzRect(spacerFrame).minX
        expandedWindows = barWindows(onScreen: true).filter { !own.contains($0.id) && $0.frame.maxX <= edge + 1 && screenRect.intersects($0.frame) }
    }
    func refresh() {
        guard let mf = frames.frame(main), let pf = frames.frame(permanent), let sf = frames.frame(spacer) else { set(\.geometryUnavailable, ready); updateIcon(); return }
        guard NSScreen.screens.contains(where: { $0.frame.contains(mf) }) else { set(\.geometryUnavailable, ready); updateIcon(); return }
        set(\.geometryUnavailable, false)
        set(\.orderBroken, !Geometry.ordered(main: mf, spacer: sf, permanent: pf))
        if state == .all {
            let own = Set([main, spacer, permanent].compactMap { frames.id($0!) })
            // Counts are sampled only while all sections are expanded.
            let screen = mainScreen ?? NSScreen.main!
            let sampled = barWindows(onScreen: true).filter { !own.contains($0.id) && quartzRect(screen.frame).intersects($0.frame) }
            set(\.hasCountSample, !sampled.isEmpty)
            let edges = (spacer: quartzRect(sf).minX, permanent: quartzRect(pf).minX)
            set(\.counts, [BarSection.alwaysHidden, .hidden, .visible].map { section in sampled.filter { Geometry.section(x: $0.frame.midX, spacer: edges.spacer, permanent: edges.permanent) == section }.count })
        }
        if state != .collapsed, let screen = mainScreen, let right = screen.auxiliaryTopRightArea, let left = screen.auxiliaryTopLeftArea {
            let notch = CGRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top, width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
            set(\.notchCount, Geometry.obscured(barWindows(onScreen: true), screen: quartzRect(screen.frame), notch: quartzRect(notch)).count)
        } else { set(\.notchCount, 0) }
        updateIcon()
    }
    /// Assigns a published value only when it changes; an unconditional assignment
    /// re-renders the whole settings window on every one-second tick.
    func set<T: Equatable>(_ path: ReferenceWritableKeyPath<AppModel, T>, _ value: T) {
        if self[keyPath: path] != value { self[keyPath: path] = value }
    }
    /// Touches the status items only when something visible changed. Re-setting the image or
    /// title every tick makes macOS 26 re-render the item, which shows as menu bar flicker.
    func updateIcon() {
        guard let main, let permanent else { return }
        let expanded = state != .collapsed, badge = config.notchBadge && notchCount > 0
        let hidden = (sectionCounts?[.hidden] ?? 0) + (state == .all ? 0 : sectionCounts?[.alwaysHidden] ?? 0)
        let label = t("MacUtil Bar，", "MacUtil Bar, ") + (state == .collapsed ? t("已收起 \(hidden) 个图标，按下以展开", "\(hidden) icons collapsed, press to reveal") : t("已展开，按下以收起", "expanded, press to collapse"))
        let title = config.divider == "line" ? "│" : config.divider == "dot" ? "•" : "‹‹"
        let key = "\(expanded)|\(badge)|\(hidingUnavailable)|\(title)|\(label)"
        guard key != iconKey || main.button?.image == nil else { return }
        iconKey = key
        if traceUpdates { print("trace status-item write", key) }
        main.button?.image = barIcon(expanded: expanded, badge: badge, failed: hidingUnavailable)
        main.button?.setAccessibilityLabel(label)
        if permanent.button?.title != title { permanent.button?.title = title }
        if permanent.button?.appearsDisabled != true { permanent.button?.appearsDisabled = true }
    }
    func tick() {
        ticks += 1
        reload(); refresh()
        if settings?.isVisible == true || search.isVisible {
            let trusted = accessibilityTrusted
            if trusted != axTrusted { axTrusted = trusted; if trusted { scanItems() } else { liveItems = []; records = [:]; layout = [.visible: [], .hidden: [], .alwaysHidden: []]; itemsLoaded = false } }
            if ticks % 5 == 0 { refreshLogin(); let current = SystemSpacing.current; if current != spacing { spacing = current } }
        }
        if itemConsumers > 0 && ticks % 2 == 0 && moving == nil { scanItems() }
        guard !suspended, ready, moving == nil else { return }
        if collapse.tick(delay: config.autoCollapse, paused: pointerInBar() || menuOpen || menusVisible() || search.isVisible, expanded: state != .collapsed) { setState(.collapsed) }
    }
    func reload() {
        do { let next = try file.read(); set(\.error, ""); if next != config { config = next; if main != nil { applyConfig() } } }
        catch { set(\.error, error.localizedDescription) }
    }
    func save(_ change: (inout Configuration) -> Void) {
        var next = config; change(&next)
        do { try file.write(next); config = next; error = ""; applyConfig() } catch { self.error = error.localizedDescription }
    }
    func applyConfig() {
        if recordingSlot == nil {
            shortcutFailed = !hotkeys.register(config.shortcut, for: .toggle)
            searchShortcutFailed = !hotkeys.register(config.searchShortcut, for: .search)
        }
        NSApp.appearance = config.appearance == "system" ? nil : NSAppearance(named: config.appearance == "dark" ? .darkAqua : .aqua)
        installMonitors(); updateIcon()
    }

    // MARK: Login item — changed only from the explicit settings switch.
    func refreshLogin() {
        let next: LoginState
        switch SMAppService.mainApp.status {
        case .enabled: next = .on
        case .requiresApproval: next = .needsApproval
        case .notRegistered: next = .off
        default: next = .unavailable
        }
        set(\.loginState, next)
    }
    func setLogin(_ enabled: Bool) {
        guard !loginBusy else { return }
        loginBusy = true; loginError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { failure = error.localizedDescription }
            DispatchQueue.main.async {
                self.loginBusy = false; self.loginError = failure; self.refreshLogin()
                if failure == nil { self.save { $0.launchAtLogin = enabled } }
            }
        }
    }

    // MARK: Icons (Accessibility)
    func scanItems(completion: (() -> Void)? = nil) {
        guard axTrusted else { completion?(); return }
        let scan: (@escaping ([AXItemRecord]) -> Void) -> Void = demoItems ? { [weak self] done in DispatchQueue.main.async { done(self?.demoRecords() ?? []) } } : identifier.scan
        scan { [weak self] found in
            guard let self else { return }
            self.records = Dictionary(found.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.liveItems = found.map(\.item)
            let next = self.dividers.map { ItemLayout.grouped(self.liveItems, dividers: $0) } ?? [.visible: self.liveItems, .hidden: [], .alwaysHidden: []]
            func signature(_ groups: [BarSection: [MenuBarItem]]) -> [String] {
                BarSection.allCases.flatMap { section in (groups[section] ?? []).map { "\(section.rawValue)|\($0.id)|\($0.displayName)|\($0.detail)|\($0.pid)" } }
            }
            if signature(next) != signature(self.layout) { self.layout = next }
            if !self.itemsLoaded { self.itemsLoaded = true }
            completion?()
        }
    }
    func section(of item: MenuBarItem) -> BarSection { dividers?.section(of: item.frame) ?? .visible }
    /// Moves an icon to another section, verified from fresh AX frames; retries twice.
    func move(_ id: String, to section: BarSection) {
        perform(id, attempt: 0, restore: state) { item, dividers in
            dividers.section(of: item.frame) == section ? nil : ItemLayout.target(for: section, dividers: dividers)
        } verify: { item, dividers in dividers.section(of: item.frame) == section }
    }
    /// Swaps an icon with its neighbour inside its section (−1 = left/up, +1 = right/down).
    func move(_ id: String, by offset: Int) {
        var expected: String?
        perform(id, attempt: 0, restore: state) { item, dividers in
            let row = ItemLayout.grouped(self.liveItems, dividers: dividers)[dividers.section(of: item.frame)] ?? []
            guard let index = row.firstIndex(where: { $0.id == id }), row.indices.contains(index + offset) else { return nil }
            expected = row[index + offset].id
            return ItemLayout.target(adjacentTo: row[index + offset].frame, before: offset < 0)
        } verify: { item, dividers in
            guard let expected, let neighbour = self.liveItems.first(where: { $0.id == expected }) else { return false }
            return offset < 0 ? item.frame.maxX <= neighbour.frame.minX + 1 : item.frame.minX >= neighbour.frame.maxX - 1
        }
    }
    /// Whether a new move may start now (one move at a time; needs verified, correctly ordered dividers).
    var canMove: Bool { axTrusted && ready && !geometryUnavailable && !orderBroken && moving == nil }
    private func perform(_ id: String, attempt: Int, restore previous: RevealState, target: @escaping (MenuBarItem, Dividers) -> CGPoint?, verify: @escaping (MenuBarItem, Dividers) -> Bool) {
        guard canMove else { return }
        moving = id; moveErrors[id] = nil
        let finish: (String?) -> Void = { [weak self] failure in
            guard let self else { return }
            self.moving = nil; self.moveErrors[id] = failure
            self.scanItems()
            if previous != .all && self.canApply(previous) { self.setState(previous) }
        }
        runAttempt(id, number: attempt, target: target, verify: verify, finish: finish)
    }
    /// One drag attempt; `moving` stays set across retries so nothing else can start or collapse the bar.
    private func runAttempt(_ id: String, number: Int, target: @escaping (MenuBarItem, Dividers) -> CGPoint?, verify: @escaping (MenuBarItem, Dividers) -> Bool, finish: @escaping (String?) -> Void) {
        guard axTrusted, ready, !geometryUnavailable, !orderBroken else {
            return finish(t("菜单栏状态已变化，移动已取消。", "The menu bar changed, so the move was cancelled."))
        }
        // Expand everything so both the icon and the destination are on screen.
        setState(.all)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.scanItems {
                guard let item = self.liveItems.first(where: { $0.id == id }), let dividers = self.dividers else {
                    return finish(self.t("找不到这个图标，可能已被它的 App 移除。", "This icon is gone; its app may have removed it."))
                }
                guard let point = target(item, dividers) else { return finish(nil) }
                guard self.isOnScreen(item.frame) else {
                    return finish(self.t("图标不在屏幕上（可能被刘海挡住），请先手动 ⌘ 拖动。", "The icon is off screen (possibly behind the notch); ⌘-drag it manually first."))
                }
                ItemMover.drag(from: CGPoint(x: item.frame.midX, y: item.frame.midY), to: point) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.scanItems {
                            guard let moved = self.liveItems.first(where: { $0.id == id }), let dividers = self.dividers else { return finish(self.t("移动后找不到图标。", "The icon could not be found after moving.")) }
                            if verify(moved, dividers) { return finish(nil) }
                            if number < 2 { self.runAttempt(id, number: number + 1, target: target, verify: verify, finish: finish) }
                            else { finish(self.t("移动未生效，请重试或手动 ⌘ 拖动。", "The move did not take effect. Retry or ⌘-drag it manually.")) }
                        }
                    }
                }
            }
        }
    }
    private func isOnScreen(_ frame: CGRect) -> Bool {
        NSScreen.screens.contains { quartzRect($0.frame).contains(CGPoint(x: frame.midX, y: frame.midY)) }
    }
    /// Opens an icon's menu, revealing its section first if needed.
    func press(_ id: String) {
        guard let record = records[id] else { return }
        let section = section(of: record.item)
        let needed: RevealState? = section == .alwaysHidden && state != .all ? .all : section == .hidden && state == .collapsed ? .revealed : nil
        if let needed, canApply(needed) { setState(needed) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (needed == nil ? 0.05 : 0.45)) { ItemMover.press(record) }
    }
    func applySpacing(_ value: Int?) { SystemSpacing.apply(value); spacing = SystemSpacing.current }

    // MARK: Triggers
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
        guard pointerInBar(), !menuOpen, moving == nil else { hoverStart = nil; return }
        if event.type == .scrollWheel && abs(event.scrollingDeltaY) > 0.5 { if config.scroll { setState(event.scrollingDeltaY < 0 ? .revealed : .collapsed) }; return }
        guard config.hover, state == .collapsed, isEmptyHoverSpace() else { hoverStart = nil; return }
        if hoverStart == nil {
            let started = Date(); hoverStart = started
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(config.hoverDelay) / 1000) { [weak self] in
                guard let self, self.hoverStart == started, self.pointerInBar(), self.isEmptyHoverSpace(), !self.suspended else { return }; self.setState(.revealed); self.hoverStart = nil
            }
        }
    }
    /// Conservative empty space: a 40pt band left of the leftmost visible icon, never the app-menu half or the notch.
    func isEmptyHoverSpace() -> Bool {
        guard let screen = mainScreen else { return false }
        let p = NSEvent.mouseLocation
        let windows = barWindows(onScreen: true).filter { $0.frame.width < 200 && quartzRect(screen.frame).intersects($0.frame) }
        let q = CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - p.y)
        let edge = windows.map(\.frame.minX).min() ?? screen.frame.maxX
        return p.x >= edge - 40 && p.x > (screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX) && !windows.contains { $0.frame.contains(q) }
    }

    // MARK: Menu
    func showMenu() {
        let menu = NSMenu(); menu.delegate = self
        if geometryUnavailable { menu.addItem(withTitle: "⚠︎ " + t("菜单栏图标位置未确认", "Menu bar position unverified"), action: #selector(openSettingsAction), keyEquivalent: "") }
        if orderBroken { menu.addItem(withTitle: "⚠︎ " + t("分隔符顺序异常，点击修复", "Dividers out of order — Fix"), action: #selector(repair), keyEquivalent: "") }
        if hidingUnavailable { menu.addItem(withTitle: "⚠︎ " + t("当前系统无法隐藏图标", "Hiding unavailable on this system"), action: #selector(openSettingsAction), keyEquivalent: "") }
        if menu.items.count > 0 { menu.addItem(.separator()) }
        let all = menu.addItem(withTitle: state == .all ? t("收起全部图标", "Hide All Icons") : t("显示全部图标", "Show All Icons"), action: #selector(all), keyEquivalent: "")
        all.keyEquivalentModifierMask = []
        if axTrusted {
            let item = menu.addItem(withTitle: t("搜索菜单栏图标…", "Search Menu Bar Icons…"), action: #selector(openSearch), keyEquivalent: "")
            if let parsed = Shortcut.parse(config.searchShortcut) { item.keyEquivalent = parsed.key; item.keyEquivalentModifierMask = modifierMask(parsed.modifiers) }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: t("设置…", "Settings…"), action: #selector(openSettingsAction), keyEquivalent: ",")
        menu.addItem(withTitle: t("退出 MacUtil Bar", "Quit MacUtil Bar"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }; activeMenu = menu
        main.menu = menu; main.button?.performClick(nil); main.menu = nil
    }
    private func modifierMask(_ names: Set<String>) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if names.contains("ctrl") { flags.insert(.control) }; if names.contains("option") { flags.insert(.option) }
        if names.contains("shift") { flags.insert(.shift) }; if names.contains("cmd") { flags.insert(.command) }
        return flags
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
    @objc func openSearch() { search.show() }
    @objc func openSettingsAction() { openSettings(page: nil) }
    func openSettings() { openSettings(page: nil) }
    func openSettings(page: SettingsPage?) {
        if let page { self.page = page }
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsLayout.defaultSize), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "MacUtil Bar"; window.toolbarStyle = .unified; window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false; window.delegate = self
            window.contentMinSize = SettingsLayout.minimumSize
            let controller = NSHostingController(rootView: SettingsView(model: self))
            // Pages have different ideal heights; never let SwiftUI resize the window past the screen.
            controller.sizingOptions = []
            window.contentViewController = controller
            window.setContentSize(SettingsLayout.defaultSize)
            window.center(); window.setFrameAutosaveName("MacUtilBar.Settings")
            settings = window
        }
        set(\.axTrusted, accessibilityTrusted); refreshLogin(); set(\.spacing, SystemSpacing.current)
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settings else { return }
        settings = nil
    }
    func route(_ url: URL) {
        guard let route = Route(url: url) else { return }
        switch route {
        case .toggle: toggle(); case .show: setState(.revealed); case .hide: setState(.collapsed); case .showAll: setState(.all)
        case .settings: openSettings(); case .search: search.show()
        }
    }
    func stop() { spacer.length = 8; permanent.length = 22; monitors.forEach(NSEvent.removeMonitor); timer?.invalidate() }
}
