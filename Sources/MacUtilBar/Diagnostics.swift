import AppKit
import SwiftUI
import MacUtilBarCore

extension AppModel {
    /// Opt-in development probe: creates only our own sacrificial status item.
    /// Uses window frames, never AX, screen capture, or synthetic input.
    func diagnose(to directory: String) {
        config.autoCollapse = 0
        UserDefaults.standard.set(3, forKey: "NSStatusItem Preferred Position MacUtilBar.Probe")
        let probe = NSStatusBar.system.statusItem(withLength: 24)
        probe.autosaveName = "MacUtilBar.Probe"; probe.button?.title = "◇"
        var samples: [[String: Any]] = []
        func sample(_ label: String) {
            func rect(_ item: NSStatusItem) -> [String: Any] {
                guard let r = self.frames.frame(item) else { return ["available":false] }
                return ["available":true,"x":r.minX,"y":r.minY,"width":r.width,"height":r.height]
            }
            let windows = barWindows().map { ["id":Double($0.id),"x":$0.frame.minX,"y":$0.frame.minY,"width":$0.frame.width,"height":$0.frame.height] }
            samples.append(["state":label,"main":rect(self.main),"spacer":rect(self.spacer),"permanent":rect(self.permanent),"probe":rect(probe),"windows":windows,"orderBroken":self.orderBroken,"hidingUnavailable":self.hidingUnavailable])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.frames.identify([probe]) {} }
        setState(.all)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            sample("all-before"); self.setState(.collapsed)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                sample("collapsed"); self.setState(.revealed)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    sample("revealed"); self.setState(.all)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        sample("all-after")
                        let url = URL(fileURLWithPath: directory)
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        if let data = try? JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url.appendingPathComponent("host-frames.json")) }
                        // Settings screenshots are captured from the real window (screencapture -l);
                        // offscreen caching cannot render the split view's materials.
                        NSStatusBar.system.removeStatusItem(probe); NSApp.terminate(nil)
                    }
                }
            }
        }
    }
}
