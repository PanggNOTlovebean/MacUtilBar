import AppKit
import Carbon
import MacUtilBarCore

func barWindows(onScreen: Bool = false) -> [BarWindow] {
    let options: CGWindowListOption = onScreen ? .optionOnScreenOnly : .optionAll
    let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { item in
        guard item[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
              let bounds = item[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds), let id = item[kCGWindowNumber as String] as? UInt32 else { return nil }
        return BarWindow(id: id, frame: frame)
    }
}
/// AppKit (bottom-left) ↔ Quartz (top-left) global coordinates. The conversion is its own inverse.
func quartzRect(_ rect: CGRect) -> CGRect {
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
}
func menusVisible() -> Bool {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { ($0[kCGWindowLayer as String] as? Int) == 101 }
}

/// Carbon global hotkeys; no Accessibility permission required.
final class HotKeys {
    enum Slot: UInt32 { case toggle = 1, search = 2 }
    private var references: [Slot: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    var actions: [Slot: () -> Void] = [:]
    static let keyCodes: [String: UInt32] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46]
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            guard let data, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(data).takeUnretainedValue()
            guard let slot = Slot(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { hotKeys.actions[slot]?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    /// Returns false when the shortcut is invalid or already taken by another app.
    func register(_ shortcut: String, for slot: Slot) -> Bool {
        if let reference = references.removeValue(forKey: slot) { UnregisterEventHotKey(reference) }
        if shortcut.isEmpty { return true }
        guard let parsed = Shortcut.parse(shortcut), let key = Self.keyCodes[parsed.key] else { return false }
        let flags: [String: Int] = ["ctrl": controlKey, "option": optionKey, "shift": shiftKey, "cmd": cmdKey]
        let mods = parsed.modifiers.reduce(UInt32(0)) { $0 | UInt32(flags[$1] ?? 0) }
        var reference: EventHotKeyRef?
        guard RegisterEventHotKey(key, mods, EventHotKeyID(signature: 0x4D554252, id: slot.rawValue), GetApplicationEventTarget(), 0, &reference) == noErr, let reference else { return false }
        references[slot] = reference
        return true
    }
    func suspend() { for (_, reference) in references { UnregisterEventHotKey(reference) }; references = [:] }
    deinit { suspend(); if let handler { RemoveEventHandler(handler) } }
}

/// Family template icon: rounded bar outline, chevron and two item blocks.
func barIcon(expanded: Bool, badge: Bool, failed: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSColor.labelColor.setStroke(); NSColor.labelColor.setFill()
        let outline = NSBezierPath(roundedRect: NSRect(x: 1, y: 4, width: 16, height: 10), xRadius: 2.5, yRadius: 2.5)
        outline.lineWidth = 1.4; outline.stroke()
        let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: expanded ? 4 : 7, y: 6.5)); arrow.line(to: NSPoint(x: expanded ? 7 : 4, y: 9)); arrow.line(to: NSPoint(x: expanded ? 4 : 7, y: 11.5))
        arrow.lineWidth = 1.4; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
        for x in [9.0, 12.5] { NSBezierPath(roundedRect: NSRect(x: x, y: 7, width: 2, height: 4), xRadius: 0.6, yRadius: 0.6).fill() }
        if failed { ("!" as NSString).draw(at: NSPoint(x: 13, y: 10), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: NSColor.labelColor]) }
        else if badge { NSBezierPath(ovalIn: NSRect(x: 14, y: 14, width: 3.5, height: 3.5)).fill() }
        return true
    }
    image.isTemplate = true; return image
}

/// Bar brand mark for settings and the app icon (purple gradient tile).
enum BrandColors {
    static let light = NSColor(red: 0.635, green: 0.482, blue: 1, alpha: 1)   // #A27BFF
    static let dark = NSColor(red: 0.416, green: 0.247, blue: 0.839, alpha: 1) // #6A3FD6
}
