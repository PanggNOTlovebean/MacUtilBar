import Foundation

public struct Configuration: Equatable {
    public var language = "system"
    public var appearance = "system"
    public var launchAtLogin = false
    public var hover = false
    public var hoverDelay = 300
    public var scroll = true
    public var shortcut = "ctrl+option+b"
    public var autoCollapse = 10
    public var collapseOnSwitch = false
    public var divider = "chevron"
    public var notchBadge = true
    public init() {}
    public enum Invalid: Error, LocalizedError {
        case value(String)
        public var errorDescription: String? { if case .value(let s) = self { return "Invalid configuration: \(s)" }; return nil }
    }
    public init(toml: String) throws {
        self.init()
        var section = "", seen = Set<String>()
        for raw in toml.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                guard ["core", "reveal", "appearance_items"].contains(section) else { throw Invalid.value(line) }
                continue
            }
            let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2 else { throw Invalid.value(line) }
            let key = section + "." + pair[0], value = pair[1]
            guard seen.insert(key).inserted else { throw Invalid.value(key) }
            func str() throws -> String {
                guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { throw Invalid.value(key) }
                let s = String(value.dropFirst().dropLast())
                guard !s.contains("\""), !s.contains("\\") else { throw Invalid.value(key) }
                return s
            }
            func bool() throws -> Bool { guard let b = Bool(value) else { throw Invalid.value(key) }; return b }
            func number(_ range: ClosedRange<Int>) throws -> Int { guard let n = Int(value), range.contains(n) else { throw Invalid.value(key) }; return n }
            switch key {
            case "core.language": language = try str()
            case "core.appearance": appearance = try str()
            case "core.launch_at_login": launchAtLogin = try bool()
            case "reveal.click": guard try bool() else { throw Invalid.value(key) }
            case "reveal.hover": hover = try bool()
            case "reveal.hover_delay_ms": hoverDelay = try number(100...3000)
            case "reveal.scroll": scroll = try bool()
            case "reveal.toggle_shortcut": shortcut = try str()
            case "reveal.auto_collapse_seconds": autoCollapse = try number(0...3600)
            case "reveal.collapse_on_app_switch": collapseOnSwitch = try bool()
            case "appearance_items.divider_style": divider = try str()
            case "appearance_items.show_notch_badge": notchBadge = try bool()
            default: throw Invalid.value(key)
            }
        }
        guard ["system", "zh-Hans", "en"].contains(language), ["system", "light", "dark"].contains(appearance), ["chevron", "line", "dot"].contains(divider), Shortcut.parse(shortcut) != nil || shortcut.isEmpty else { throw Invalid.value("unsupported value") }
    }
    public var toml: String {
        """
        # MacUtil Bar 1.0 — supported TOML subset; unknown keys are rejected.
        [core]
        language = "\(language)"
        appearance = "\(appearance)"
        launch_at_login = \(launchAtLogin)

        [reveal]
        click = true
        hover = \(hover)
        hover_delay_ms = \(hoverDelay)
        scroll = \(scroll)
        toggle_shortcut = "\(shortcut)"
        auto_collapse_seconds = \(autoCollapse)
        collapse_on_app_switch = \(collapseOnSwitch)

        [appearance_items]
        divider_style = "\(divider)"
        show_notch_badge = \(notchBadge)

        """
    }
}
public enum Shortcut {
    public static func parse(_ value: String) -> (key: String, modifiers: Set<String>)? {
        let parts = value.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last, key.count == 1, "abcdefghijklmnopqrstuvwxyz0123456789".contains(key) else { return nil }
        let mods = Set(parts.dropLast())
        guard mods.count == parts.count - 1, !mods.isEmpty, mods.isSubset(of: ["ctrl", "option", "shift", "cmd"]) else { return nil }
        return (key, mods)
    }
}
/// Compare the last read bytes before writing, so external edits are never silently overwritten.
public final class ConfigurationFile {
    public let url: URL
    private var lastRead: Data?
    public init(url: URL) { self.url = url }
    public func read() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { lastRead = nil; return Configuration() }
        let data = try Data(contentsOf: url)
        let config = try Configuration(toml: String(decoding: data, as: UTF8.self))
        lastRead = data
        return config
    }
    public func write(_ config: Configuration) throws {
        let data = try? Data(contentsOf: url)
        guard data == lastRead else { throw Configuration.Invalid.value("file changed externally; reload before saving") }
        _ = try Configuration(toml: config.toml)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let next = Data(config.toml.utf8)
        try next.write(to: url, options: .atomic)
        lastRead = next
    }
}
