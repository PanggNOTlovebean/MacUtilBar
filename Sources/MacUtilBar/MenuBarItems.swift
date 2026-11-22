import AppKit
import ApplicationServices
import MacUtilBarCore

enum Accessibility {
    static var trusted: Bool { AXIsProcessTrusted() }
    /// Only called from an explicit user action. Shows the system prompt once and opens the privacy pane.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) { openSettings() }
    }
    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

struct AXItemRecord {
    let item: MenuBarItem
    let element: AXUIElement
}

/// Reads every app's `AXExtrasMenuBar` on a serial background queue with a short
/// messaging timeout, so an unresponsive app cannot stall the scan.
final class ItemIdentifier {
    private let queue = DispatchQueue(label: "local.macutilbar.accessibility", qos: .userInitiated)
    private var running: [([AXItemRecord]) -> Void]?
    private var waiting: [([AXItemRecord]) -> Void] = []
    static let systemBundles: Set<String> = ["com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.Spotlight", "com.apple.TextInputMenuAgent", "com.apple.Siri"]

    /// Every caller receives a scan that *started* after its request, so a move never sees
    /// frames captured before the bar expanded. Requests made during a scan share one follow-up scan.
    func scan(completion: @escaping ([AXItemRecord]) -> Void) {
        if running != nil { waiting.append(completion) } else { start([completion]) }
    }
    private func start(_ callbacks: [([AXItemRecord]) -> Void]) {
        running = callbacks
        let own = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != own && !$0.isTerminated }
            .map { (pid: $0.processIdentifier, bundle: $0.bundleIdentifier ?? "", name: $0.localizedName ?? "") }
        queue.async {
            let records = apps.flatMap { Self.read(pid: $0.pid, bundle: $0.bundle, name: $0.name) }
            DispatchQueue.main.async {
                let finished = self.running ?? []; self.running = nil
                let next = self.waiting; self.waiting = []
                if !next.isEmpty { self.start(next) }
                finished.forEach { $0(records) }
            }
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        (attribute(element, name) as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent),
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: point, size: extent)
    }

    static func read(pid: pid_t, bundle: String, name: String) -> [AXItemRecord] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let bar = attribute(app, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID(),
              let children = attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        let system = systemBundles.contains(bundle)
        var seen: [String: Int] = [:]
        return children.enumerated().compactMap { index, element in
            AXUIElementSetMessagingTimeout(element, 0.25)
            guard let frame = frame(of: element) else { return nil }
            let identifier = string(element, kAXIdentifierAttribute)
            let description = string(element, kAXDescriptionAttribute)
            let title = string(element, kAXTitleAttribute)
            let help = string(element, kAXHelpAttribute)
            let label = description ?? title ?? help ?? ""
            let base = MenuBarItem.identity(bundleID: bundle.isEmpty ? "pid\(pid)" : bundle, identifier: identifier, description: description, index: index)
            seen[base, default: 0] += 1
            let id = MenuBarItem.disambiguated(base, occurrence: seen[base]!)
            // System modules (Wi-Fi, Battery…) all belong to Control Center; name them by their label.
            let appName = system && !label.isEmpty ? label : name
            return AXItemRecord(item: MenuBarItem(id: id, bundleID: bundle, appName: appName, label: label, pid: pid, frame: frame), element: element)
        }
    }
}

/// Simulates the system ⌘-drag on behalf of the user. Posting events requires
/// Accessibility; the caller must verify the result from fresh frames.
enum ItemMover {
    private static let queue = DispatchQueue(label: "local.macutilbar.mover")
    static func drag(from start: CGPoint, to end: CGPoint, completion: @escaping () -> Void) {
        queue.async {
            let source = CGEventSource(stateID: .hidSystemState)
            let original = CGEvent(source: nil)?.location ?? start
            let display = CGMainDisplayID()
            CGDisplayHideCursor(display)
            func post(_ type: CGEventType, _ point: CGPoint, command: Bool = true) {
                let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
                if command { event?.flags = .maskCommand }
                event?.post(tap: .cghidEventTap)
            }
            post(.mouseMoved, start, command: false); usleep(30_000)
            post(.leftMouseDown, start); usleep(120_000)
            let steps = 10
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)); usleep(18_000)
            }
            usleep(80_000)
            post(.leftMouseUp, end); usleep(60_000)
            CGWarpMouseCursorPosition(original)
            CGAssociateMouseAndMouseCursorPosition(1)
            CGDisplayShowCursor(display)
            DispatchQueue.main.async(execute: completion)
        }
    }
    private static let pressQueue = DispatchQueue(label: "local.macutilbar.press")
    /// Opens an icon's menu: AXPress first (no pointer movement). A status item runs its menu
    /// inside the AXPress call, so a timeout means the menu is open — only click when the
    /// element genuinely can't be pressed. Runs off the main thread.
    static func press(_ record: AXItemRecord) {
        pressQueue.async {
            AXUIElementSetMessagingTimeout(record.element, 0.25)
            let result = AXUIElementPerformAction(record.element, kAXPressAction as CFString)
            guard [.actionUnsupported, .attributeUnsupported, .invalidUIElement].contains(result) else { return }
            let frame = ItemIdentifier.frame(of: record.element) ?? record.item.frame
            let point = CGPoint(x: frame.midX, y: frame.midY)
            let source = CGEventSource(stateID: .hidSystemState)
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
        }
    }
}

/// Writes the global currentHost spacing preference only after explicit confirmation.
enum SystemSpacing {
    private static func value(_ key: String) -> Int? {
        CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int
    }
    static var current: Int? { value(SpacingPreference.spacingKey) }
    static func apply(_ spacing: Int?) {
        let values = spacing.map(SpacingPreference.values(for:))
        CFPreferencesSetValue(SpacingPreference.spacingKey as CFString, values.map { $0.spacing as CFNumber }, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSetValue(SpacingPreference.paddingKey as CFString, values.map { $0.padding as CFNumber }, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}
