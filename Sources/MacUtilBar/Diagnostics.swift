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
            func rect(_ item: NSStatusItem) -> [String: Double] {
                let r = self.frames.frame(item) ?? .zero
                return ["x":r.minX,"y":r.minY,"width":r.width,"height":r.height]
            }
            let windows = barWindows().map { ["id":Double($0.id),"x":$0.frame.minX,"y":$0.frame.minY,"width":$0.frame.width,"height":$0.frame.height] }
            samples.append(["state":label,"main":rect(self.main),"spacer":rect(self.spacer),"permanent":rect(self.permanent),"probe":rect(probe),"windows":windows,"orderBroken":self.orderBroken,"hidingUnavailable":self.hidingUnavailable])
        }
        frames.identify([probe]) {}
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
                        self.openSettings()
                        self.refresh()
                        self.timer?.invalidate()
                        for language in ["zh-Hans", "en"] {
                            self.config.language = language
                            for tab in [0, 1] {
                                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                                    self.settings?.appearance = NSAppearance(named: appearance)
                                    self.settings?.contentView = NSHostingView(rootView: SettingsView(model: self, initialTab: tab))
                                    self.settings?.setContentSize(NSSize(width: 620, height: 520))
                                    if let view = self.settings?.contentView {
                                        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                                        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                                            view.cacheDisplay(in: view.bounds, to: bitmap)
                                            try? bitmap.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent("settings-\(language)-\(tab)-\(appearance.rawValue).png"))
                                        }
                                    }
                                }
                            }
                        }
                        NSStatusBar.system.removeStatusItem(probe); NSApp.terminate(nil)
                    }
                }
            }
        }
    }
}
