import Foundation
import CoreGraphics


public enum Version {
    public static let current = "1.0.0"
    public static let build = "1"
}
public enum RevealState: String, Codable { case collapsed, revealed, all }
public enum Route: String, CaseIterable {
    case toggle, show, hide, showAll = "show-all", settings
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "macutilbar", let host = url.host else { return nil }
        self.init(rawValue: host)
    }
}
public struct BarWindow: Equatable, Codable {
    public var id: UInt32
    public var frame: CGRect
    public init(id: UInt32, frame: CGRect) { self.id = id; self.frame = frame }
}
public enum Section: String { case visible, hidden, alwaysHidden }
public enum Geometry {
    public static func collapseLength(widths: [Double]) -> Double { min(10_000, max(0, widths.max() ?? 0) + 200) }
    public static func section(x: Double, main: Double, permanent: Double) -> Section {
        x >= main ? .visible : x >= permanent ? .hidden : .alwaysHidden
    }
    public static func ordered(main: CGRect, spacer: CGRect, permanent: CGRect) -> Bool {
        permanent.minX < spacer.minX && spacer.maxX <= main.minX + 2
    }
    public static func obscured(_ windows: [BarWindow], screen: CGRect, notch: CGRect?) -> [BarWindow] {
        guard let notch else { return [] }
        return windows.filter { $0.frame.midY >= screen.minY && $0.frame.midY <= screen.maxY && $0.frame.maxX > screen.minX && $0.frame.minX < notch.maxX }
    }
}
public struct HidingSelfTest {
    public private(set) var failures = 0
    public init() {}
    public mutating func check(before: [BarWindow], after: [BarWindow], screens: [CGRect], main: CGRect) -> Bool? {
        let mainVisible = screens.contains { $0.contains(main) }
        if before.isEmpty && mainVisible { return nil }
        let hidden = before.allSatisfy { old in
            guard let new = after.first(where: { $0.id == old.id }) else { return true }
            return !screens.contains { $0.intersects(new.frame) }
        }
        failures = mainVisible && hidden ? 0 : failures + 1
        return failures < 2
    }
}
public struct AutoCollapse {
    public var idleSeconds = 0
    public init() {}
    public mutating func tick(delay: Int, paused: Bool, expanded: Bool) -> Bool {
        guard expanded, delay > 0, !paused else { idleSeconds = 0; return false }
        idleSeconds += 1
        return idleSeconds >= delay
    }
}
