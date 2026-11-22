import Foundation
import CoreGraphics

public enum Version {
    public static let current = "1.1.0"
    public static let build = "4"
}
public enum RevealState: String, Codable { case collapsed, revealed, all }
public enum Route: String, CaseIterable {
    case toggle, show, hide, showAll = "show-all", settings, search
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
public enum BarSection: String, CaseIterable, Codable, Identifiable {
    case visible, hidden, alwaysHidden
    public var id: String { rawValue }
}

/// Frames of our own three status items, in Quartz (top-left origin) coordinates.
public struct Dividers: Equatable {
    public var main: CGRect
    public var spacer: CGRect
    public var permanent: CGRect
    public init(main: CGRect, spacer: CGRect, permanent: CGRect) { self.main = main; self.spacer = spacer; self.permanent = permanent }
    public var ordered: Bool { Geometry.ordered(main: main, spacer: spacer, permanent: permanent) }
    /// Icons between the spacer and the main icon stay on screen when collapsed,
    /// so the spacer (not the main icon) is the hidden-section boundary.
    public func section(of frame: CGRect) -> BarSection {
        Geometry.section(x: frame.midX, spacer: spacer.minX, permanent: permanent.minX)
    }
}

public enum Geometry {
    public static func collapseLength(widths: [Double]) -> Double { min(10_000, max(0, widths.max() ?? 0) + 200) }
    public static func section(x: Double, spacer: Double, permanent: Double) -> BarSection {
        x >= spacer ? .visible : x >= permanent ? .hidden : .alwaysHidden
    }
    public static func ordered(main: CGRect, spacer: CGRect, permanent: CGRect) -> Bool {
        permanent.minX < spacer.minX && spacer.maxX <= main.minX + 2
    }
    public static func obscured(_ windows: [BarWindow], screen: CGRect, notch: CGRect?) -> [BarWindow] {
        guard let notch else { return [] }
        return windows.filter { $0.frame.midY >= screen.minY && $0.frame.midY <= screen.maxY && $0.frame.maxX > screen.minX && $0.frame.minX < notch.maxX }
    }
}

/// A third-party or system menu bar icon identified through Accessibility.
public struct MenuBarItem: Equatable, Identifiable, Sendable {
    public var id: String
    public var bundleID: String
    public var appName: String
    public var label: String
    public var pid: Int32
    public var frame: CGRect
    public init(id: String, bundleID: String, appName: String, label: String, pid: Int32, frame: CGRect) {
        self.id = id; self.bundleID = bundleID; self.appName = appName; self.label = label; self.pid = pid; self.frame = frame
    }
    /// Stable identity: bundle ID plus AXIdentifier or AXDescription, else the index within the app.
    /// AXTitle is deliberately excluded: live-text items (meters, timers) change it constantly.
    public static func identity(bundleID: String, identifier: String?, description: String?, index: Int) -> String {
        for (kind, value) in [("id", identifier), ("desc", description)] {
            if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty { return "\(bundleID)#\(kind)=\(value)" }
        }
        return "\(bundleID)#\(index)"
    }
    /// Second and later items sharing an identity within one app get a numeric suffix, keeping IDs unique.
    public static func disambiguated(_ identity: String, occurrence: Int) -> String {
        occurrence <= 1 ? identity : "\(identity)~\(occurrence)"
    }
    /// Human-readable name: the app name, with the AX label when it adds information.
    public var displayName: String { appName.isEmpty ? (label.isEmpty ? bundleID : label) : appName }
    public var detail: String { label.isEmpty || label == appName ? bundleID : label }
}

public enum ItemLayout {
    /// Items grouped by section, each sorted left to right as on the menu bar.
    public static func grouped(_ items: [MenuBarItem], dividers: Dividers) -> [BarSection: [MenuBarItem]] {
        var result: [BarSection: [MenuBarItem]] = [.visible: [], .hidden: [], .alwaysHidden: []]
        for item in items.sorted(by: { $0.frame.minX < $1.frame.minX }) { result[dividers.section(of: item.frame), default: []].append(item) }
        return result
    }
    /// Drop point for a ⌘-drag that places an icon at the right end of `section` (closest to the main icon).
    public static func target(for section: BarSection, dividers: Dividers) -> CGPoint {
        switch section {
        case .visible: return CGPoint(x: dividers.main.maxX + 2, y: dividers.main.midY)
        case .hidden: return CGPoint(x: dividers.spacer.minX + 1, y: dividers.spacer.midY)
        case .alwaysHidden: return CGPoint(x: dividers.permanent.minX + 1, y: dividers.permanent.midY)
        }
    }
    /// Drop point that inserts an icon immediately left (`before`) or right of a neighbour.
    public static func target(adjacentTo neighbour: CGRect, before: Bool) -> CGPoint {
        CGPoint(x: before ? neighbour.minX + 2 : neighbour.maxX - 2, y: neighbour.midY)
    }
    /// Case- and diacritic-insensitive match across name, label and bundle ID. Empty query matches everything.
    public static func filter(_ items: [MenuBarItem], query: String) -> [MenuBarItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let haystack = [item.appName, item.label, item.bundleID].joined(separator: " ")
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}

/// Global status item spacing preference (NSStatusItemSpacing / NSStatusItemSelectionPadding).
public enum SpacingPreference {
    public static let spacingKey = "NSStatusItemSpacing"
    public static let paddingKey = "NSStatusItemSelectionPadding"
    public static let range = 0...16
    public static let systemDefault = 16
    /// Selection padding follows spacing, but never below 4pt so icons stay clickable.
    public static func values(for spacing: Int) -> (spacing: Int, padding: Int) {
        let value = min(range.upperBound, max(range.lowerBound, spacing))
        return (value, max(4, value))
    }
}

public struct HidingSelfTest {
    public private(set) var failures = 0
    public private(set) var visibleRemainder = 0
    public init() {}
    public mutating func check(before: [BarWindow], after: [BarWindow], screens: [CGRect], main: CGRect) -> Bool? {
        let mainVisible = screens.contains { $0.contains(main) }
        if before.isEmpty && mainVisible { failures = 0; visibleRemainder = 0; return nil }
        let hidden = before.filter { old in
            guard let new = after.first(where: { $0.id == old.id }) else { return true }
            return !screens.contains { $0.intersects(new.frame) }
        }
        visibleRemainder = before.count - hidden.count
        // Mandatory system indicators can relocate to stay visible. Report them
        // separately; only declare the entire mechanism unavailable when no
        // target actually hid, or our own control disappeared.
        failures = mainVisible && !hidden.isEmpty ? 0 : failures + 1
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

/// A width change alone can coincide with another app updating its menu item.
/// Bind only a unique window whose width also returns to its original value.
public enum StatusWindowCalibration {
    public static func identify(before: [BarWindow], expanded: [BarWindow], restored: [BarWindow], delta: Double) -> UInt32? {
        guard delta > 0 else { return nil }
        let matches = before.filter { original in
            guard let changed = expanded.first(where: { $0.id == original.id }),
                  let final = restored.first(where: { $0.id == original.id }) else { return false }
            return original.frame.width > 0 && original.frame.height > 0 &&
                abs(changed.frame.width - original.frame.width - delta) < 0.5 &&
                abs(final.frame.width - original.frame.width) < 0.5 &&
                abs(changed.frame.height - original.frame.height) < 0.5 &&
                abs(final.frame.height - original.frame.height) < 0.5
        }
        return matches.count == 1 ? matches[0].id : nil
    }
}
