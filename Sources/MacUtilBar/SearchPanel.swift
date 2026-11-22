import AppKit
import SwiftUI
import MacUtilBarCore

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// Centered picker in the style of Paste 1.8.0: autofocused field, tabs, solid-blue selection, keycap hints.
final class SearchPanelController: NSObject, NSWindowDelegate {
    private weak var model: AppModel?
    private var panel: NSPanel?
    init(model: AppModel) { self.model = model }
    var isVisible: Bool { panel?.isVisible == true }
    func toggle() { isVisible ? close() : show() }
    func show() {
        guard let model else { return }
        if !model.axTrusted { model.openSettings(page: .icons); return }
        if panel == nil {
            let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420), styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.level = .floating; panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: SearchView(model: model, close: { [weak self] in self?.close() }))
            self.panel = panel
        } else if let host = panel?.contentView as? NSHostingView<SearchView> {
            host.rootView = SearchView(model: model, close: { [weak self] in self?.close() })
        }
        model.itemConsumers += 1; model.scanItems()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen, let panel {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + frame.height * 0.62 - panel.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        model?.itemConsumers -= 1
    }
    func windowDidResignKey(_ notification: Notification) { close() }
}

struct SearchView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var query = ""
    @State private var tab: BarSection? = nil
    @State private var selection = 0
    @State private var hovered: String?
    @FocusState private var focused: Bool
    private var results: [(item: MenuBarItem, section: BarSection)] {
        let groups = model.grouped
        let order: [BarSection] = [.visible, .hidden, .alwaysHidden]
        return order.filter { tab == nil || tab == $0 }.flatMap { section in
            ItemLayout.filter((groups[section] ?? []).reversed(), query: query).map { ($0, section) }
        }
    }
    var body: some View {
        let rows = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 15))
                TextField(model.t("搜索菜单栏图标…", "Search menu bar icons…"), text: $query)
                    .textFieldStyle(.plain).font(.system(size: 17)).focused($focused)
                    .onSubmit { open(rows, reveal: NSEvent.modifierFlags.contains(.option)) }
                Text(model.t("\(rows.count) 个图标", "\(rows.count) icons")).font(SettingsTokens.detailFont).foregroundStyle(.secondary).monospacedDigit()
            }.padding(.horizontal, 16).frame(height: 50)
            HStack(spacing: 18) {
                tabButton(nil, model.t("全部", "All"))
                ForEach([BarSection.visible, .hidden, .alwaysHidden]) { tabButton($0, $0.title(model)) }
                Spacer()
            }.padding(.horizontal, 16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.item.id) { index, row in
                            resultRow(row.item, row.section, selected: index == selection).id(index)
                                .onTapGesture { selection = index; open(rows, reveal: false) }
                                .onHover { hovered = $0 ? row.item.id : (hovered == row.item.id ? nil : hovered) }
                        }
                    }.padding(6)
                }
                .overlay {
                    if !model.itemsLoaded { ProgressView() }
                    else if rows.isEmpty { Text(model.t("没有找到图标", "No icons found")).foregroundStyle(.secondary) }
                }
                .onChange(of: selection) { _, value in withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(value) } }
            }
            Divider()
            HStack(spacing: 14) {
                keycap("↩", model.t("打开", "Open"))
                keycap("⌥↩", model.t("显示所在分区", "Reveal section"))
                keycap("⎋", model.t("关闭", "Close"))
                Spacer()
                keycap("↑↓", model.t("选择", "Select"))
            }.padding(.horizontal, 16).frame(height: 34)
        }
        .frame(width: 560, height: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SettingsTokens.border, lineWidth: 0.5))
        .onAppear { focused = true; selection = 0 }
        .onChange(of: query) { _, _ in selection = 0 }
        .onChange(of: tab) { _, _ in selection = 0 }
        .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, rows.count - 1)); return .handled }
        .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
        .onKeyPress(.leftArrow) { guard query.isEmpty else { return .ignored }; shiftTab(-1); return .handled }
        .onKeyPress(.rightArrow) { guard query.isEmpty else { return .ignored }; shiftTab(1); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
    }
    private func shiftTab(_ delta: Int) {
        let tabs: [BarSection?] = [nil, .visible, .hidden, .alwaysHidden]
        let index = tabs.firstIndex(where: { $0 == tab }) ?? 0
        tab = tabs[(index + delta + tabs.count) % tabs.count]
    }
    private func open(_ rows: [(item: MenuBarItem, section: BarSection)], reveal: Bool) {
        guard rows.indices.contains(selection) else { return }
        let row = rows[selection]
        close()
        if reveal { model.setState(row.section == .alwaysHidden ? .all : row.section == .hidden ? .revealed : model.state) }
        else { model.press(row.item.id) }
    }
    private func tabButton(_ value: BarSection?, _ title: String) -> some View {
        Button { tab = value } label: {
            VStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: tab == value ? .semibold : .regular))
                Rectangle().fill(tab == value ? Color.accentColor : .clear).frame(height: 2)
            }.fixedSize()
        }.buttonStyle(.plain).foregroundStyle(tab == value ? Color.accentColor : .secondary)
    }
    private func resultRow(_ item: MenuBarItem, _ section: BarSection, selected: Bool) -> some View {
        HStack(spacing: 10) {
            AppIconImage(pid: item.pid, fallback: "app.dashed").frame(width: 22, height: 22)
            highlighted(item.displayName).lineLimit(1)
            Text(item.detail).font(SettingsTokens.detailFont).foregroundStyle(selected ? Color.white.opacity(0.8) : .secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(section.title(model)).font(.system(size: 11)).foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background((selected ? Color.white.opacity(0.2) : Color.primary.opacity(0.06)), in: Capsule())
        }
        .padding(.horizontal, 10).frame(height: 36)
        .foregroundStyle(selected ? .white : .primary)
        .background(selected ? Color.accentColor : hovered == item.id ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }
    /// Matching words get a yellow highlight, like Paste.
    private func highlighted(_ text: String) -> Text {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        var attributed = AttributedString(text)
        for word in words {
            var searchRange = attributed.startIndex..<attributed.endIndex
            while let range = attributed[searchRange].range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
                attributed[range].backgroundColor = Color.yellow.opacity(0.45)
                searchRange = range.upperBound..<attributed.endIndex
            }
        }
        return Text(attributed)
    }
    private func keycap(_ key: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.system(size: 10, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(SettingsTokens.border, lineWidth: 0.5))
            Text(title).font(.system(size: 11))
        }.foregroundStyle(.secondary)
    }
}
