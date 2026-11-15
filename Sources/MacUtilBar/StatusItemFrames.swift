import AppKit
import MacUtilBarCore

/// macOS 26 may host status items in Control Center and leave the local NSWindow
/// at a placeholder origin. Identify ONLY our own windows by a reversible width
/// change, with a unique before/after match; never infer another app's identity.
final class StatusItemFrames {
    private var ids: [ObjectIdentifier: UInt32] = [:]
    func id(_ item: NSStatusItem) -> UInt32? { ids[ObjectIdentifier(item)] }
    func frame(_ item: NSStatusItem) -> CGRect? {
        if let id = id(item), let window = barWindows().first(where: { $0.id == id }) { return quartzRect(window.frame) }
        guard let window = item.button?.window, window.windowNumber > 0 else { return nil }
        return window.frame
    }
    func identify(_ items: [NSStatusItem], completion: @escaping () -> Void) {
        guard let item = items.first else { completion(); return }
        let before = barWindows()
        let original = item.length
        item.length = original + 11
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let after = barWindows()
            let matches = after.filter { candidate in
                before.contains { $0.id == candidate.id && abs(candidate.frame.width - $0.frame.width - 11) < 1 }
            }
            if matches.count == 1 { self.ids[ObjectIdentifier(item)] = matches[0].id }
            item.length = original
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.identify(Array(items.dropFirst()), completion: completion) }
        }
    }
}
