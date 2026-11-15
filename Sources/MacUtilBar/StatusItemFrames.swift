import AppKit
import MacUtilBarCore

/// Require Window Server evidence; a local NSWindow can have placeholder bounds. Identify ONLY our own windows by a reversible width
/// change, with a unique before/after match; never infer another app's identity.
final class StatusItemFrames {
    private var ids: [ObjectIdentifier: UInt32] = [:]
    func id(_ item: NSStatusItem) -> UInt32? { ids[ObjectIdentifier(item)] }
    func frame(_ item: NSStatusItem) -> CGRect? {
        if let id = id(item), let window = barWindows().first(where: { $0.id == id }) { return quartzRect(window.frame) }
        guard let window = item.button?.window,
              let nativeID = UInt32(exactly: window.windowNumber),
              let measured = barWindows().first(where: { $0.id == nativeID }) else { return nil }
        return quartzRect(measured.frame)
    }
    func identify(_ items: [NSStatusItem], retry: Bool = true, completion: @escaping () -> Void) {
        guard let item = items.first else { completion(); return }
        let before = barWindows()
        let original = item.length
        item.length = original + 11
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let after = barWindows()
            item.length = original
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                let restored = barWindows()
                let matched = StatusWindowCalibration.identify(before: before, expanded: after, restored: restored, delta: 11)
                if CommandLine.arguments.contains("--diagnose") {
                    print("calibration", item.autosaveName ?? "", "matched", matched as Any)
                    for snapshot in [before, after, restored] { print(snapshot.map { "\($0.id):\($0.frame.width)" }.joined(separator: " ")) }
                }
                self.ids[ObjectIdentifier(item)] = matched
                if matched == nil && retry {
                    // Newly created items may initially use intrinsic content width.
                    // The first restoration settles their requested length; retry once.
                    self.identify(items, retry: false, completion: completion)
                } else {
                    self.identify(Array(items.dropFirst()), completion: completion)
                }
            }
        }
    }
}
