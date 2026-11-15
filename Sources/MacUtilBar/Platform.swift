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
func quartzRect(_ rect: CGRect) -> CGRect {
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
}
func menusVisible() -> Bool {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { ($0[kCGWindowLayer as String] as? Int) == 101 }
}
final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(data).takeUnretainedValue().action?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ shortcut: String) -> Bool {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        if shortcut.isEmpty { return true }
        guard let parsed = Shortcut.parse(shortcut) else { return false }
        let keys: [String: UInt32] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46]
        guard let key = keys[parsed.key] else { return false }
        let flags: [String: Int] = ["ctrl":controlKey,"option":optionKey,"shift":shiftKey,"cmd":cmdKey]
        let mods = parsed.modifiers.reduce(UInt32(0)) { $0 | UInt32(flags[$1] ?? 0) }
        return RegisterEventHotKey(key, mods, EventHotKeyID(signature: 0x4D554252, id: 1), GetApplicationEventTarget(), 0, &reference) == noErr
    }
    deinit { if let reference { UnregisterEventHotKey(reference) }; if let handler { RemoveEventHandler(handler) } }
}
func barIcon(expanded: Bool, badge: Bool, failed: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSColor.labelColor.setStroke(); NSColor.labelColor.setFill()
        let outline = NSBezierPath(roundedRect: NSRect(x: 1, y: 4, width: 16, height: 10), xRadius: 2, yRadius: 2)
        outline.lineWidth = 1.4; outline.stroke()
        let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: expanded ? 4 : 7, y: 6.5)); arrow.line(to: NSPoint(x: expanded ? 7 : 4, y: 9)); arrow.line(to: NSPoint(x: expanded ? 4 : 7, y: 11.5)); arrow.lineWidth = 1.4; arrow.stroke()
        for x in [9.0, 12.5] { NSBezierPath(roundedRect: NSRect(x: x, y: 7, width: 2, height: 4), xRadius: 0.6, yRadius: 0.6).fill() }
        if failed { ("!" as NSString).draw(at: NSPoint(x: 13, y: 10), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: NSColor.labelColor]) }
        else if badge { NSBezierPath(ovalIn: NSRect(x: 14, y: 14, width: 3, height: 3)).fill() }
        return true
    }
    image.isTemplate = true; return image
}
