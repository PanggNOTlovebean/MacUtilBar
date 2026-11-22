import AppKit
import SwiftUI
import MacUtilBarCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case icons, reveal, appearance, general
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .icons: return "menubar.rectangle"
        case .reveal: return "cursorarrow.click.2"
        case .appearance: return "paintbrush.pointed"
        case .general: return "gearshape"
        }
    }
    var color: Color {
        switch self {
        case .icons: return SettingsTokens.brand
        case .reveal: return .blue
        case .appearance: return .orange
        case .general: return Color(nsColor: .systemGray)
        }
    }
    func title(_ model: AppModel) -> String {
        switch self {
        case .icons: return model.t("菜单栏图标", "Menu Bar Icons")
        case .reveal: return model.t("展开与收起", "Reveal & Collapse")
        case .appearance: return model.t("外观", "Appearance")
        case .general: return model.t("通用", "General")
        }
    }
    var shortcut: KeyEquivalent { KeyEquivalent(Character(String((SettingsPage.allCases.firstIndex(of: self) ?? 0) + 1))) }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var visibility: NavigationSplitViewVisibility = .all
    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            List(SettingsPage.allCases, selection: Binding<SettingsPage?>(get: { model.page }, set: { if let page = $0 { model.page = page } })) { page in
                Label { Text(page.title(model)) } icon: { SettingsIconTile(symbol: page.symbol, color: page.color) }
                    .tag(page).padding(.vertical, 3)
                    .accessibilityIdentifier("settings.navigation." + page.rawValue)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: SettingsLayout.sidebarWidth, ideal: SettingsLayout.sidebarWidth, max: SettingsLayout.sidebarWidth)
            .safeAreaInset(edge: .bottom) { SidebarStatus(model: model).padding(SettingsTokens.pagePadding) }
        } detail: {
            VStack(spacing: 0) {
                SettingsNotices(model: model)
                Group {
                    switch model.page {
                    case .icons: IconsPage(model: model)
                    case .reveal: RevealPage(model: model)
                    case .appearance: AppearancePage(model: model)
                    case .general: GeneralPage(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(model.page.title(model))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .font(SettingsTokens.bodyFont)
        .toolbar { ToolbarItem(placement: .primaryAction) { StateControl(model: model) } }
        .background(pageShortcuts)
        .frame(minWidth: SettingsLayout.minimumSize.width, minHeight: SettingsLayout.minimumSize.height)
    }
    /// ⌘1 – ⌘4 switch pages.
    private var pageShortcuts: some View {
        ZStack {
            ForEach(SettingsPage.allCases) { page in
                Button("") { model.page = page }.keyboardShortcut(page.shortcut, modifiers: .command).opacity(0).accessibilityHidden(true)
            }
        }.frame(width: 0, height: 0)
    }
}

/// Live collapse state in the toolbar: Collapsed · Revealed · Show All.
struct StateControl: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Picker(model.t("菜单栏状态", "Menu bar state"), selection: Binding(get: { model.state }, set: { model.setState($0) })) {
            Text(model.t("收起", "Collapse")).tag(RevealState.collapsed)
            Text(model.t("展开", "Reveal")).tag(RevealState.revealed)
            Text(model.t("全部", "Show All")).tag(RevealState.all)
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
        .disabled(!model.canApply(.collapsed))
        .help(model.t("左键点击菜单栏图标切换收起/展开；⌥ 点击显示全部。", "Click the menu bar icon to toggle; ⌥-click to show all."))
        .accessibilityIdentifier("settings.state")
    }
}

struct SidebarStatus: View {
    @ObservedObject var model: AppModel
    private var status: (color: Color, text: String) {
        if !model.ready { return (.secondary, model.t("正在确认菜单栏位置…", "Checking menu bar…")) }
        if model.geometryUnavailable { return (.orange, model.t("菜单栏图标未显示", "Icon not in menu bar")) }
        if model.hidingUnavailable { return (.red, model.t("隐藏暂不可用", "Hiding unavailable")) }
        if model.orderBroken { return (.orange, model.t("分隔符顺序异常", "Dividers out of order")) }
        switch model.state {
        case .collapsed: return (.green, model.t("已收起", "Collapsed"))
        case .revealed: return (.green, model.t("已展开", "Revealed"))
        case .all: return (.green, model.t("全部显示", "Showing all"))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(status.color).frame(width: 7, height: 7)
                Text(status.text).font(SettingsTokens.detailFont).foregroundStyle(.secondary).lineLimit(1)
            }.accessibilityElement(children: .combine).accessibilityIdentifier("settings.status")
            Text("\(Version.current) (\(Version.build))").font(SettingsTokens.versionFont).foregroundStyle(.tertiary)
                .accessibilityIdentifier("app.version")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Problems that block the core feature are shown above every page.
struct SettingsNotices: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let notices = VStack(spacing: 8) {
            if !model.error.isEmpty {
                SettingsNotice(tone: .warning, title: model.t("配置文件有误，正在使用上次的有效设置", "Configuration error — using the last valid settings"), detail: model.error) {
                    Button(model.t("在访达中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([model.file.url]) }
                }
            }
            if model.geometryUnavailable {
                SettingsNotice(tone: .warning, title: model.t("macOS 没有显示 MacUtil Bar 的菜单栏图标", "macOS isn’t showing MacUtil Bar in the menu bar"),
                    detail: model.t("系统未给本 App 的图标分配位置，因此暂停收起，避免误藏图标。请在 系统设置 › 菜单栏 › “允许在菜单栏中显示” 中打开 MacUtil Bar；如果已经打开，先关闭再打开，然后点“重新检查”。",
                                    "The system gave this app’s icons no position, so collapsing is paused to avoid hiding icons by mistake. In System Settings › Menu Bar › “Allow in the Menu Bar”, turn MacUtil Bar on (or off and on again), then click Check Again.")) {
                    Button(model.t("打开菜单栏设置", "Open Menu Bar Settings")) { openMenuBarSettings() }
                    Button(model.t("重新检查", "Check Again")) { model.retryGeometry() }.disabled(!model.ready)
                }
            }
            if model.hidingUnavailable {
                SettingsNotice(tone: .error, title: model.t("当前 macOS 版本暂不支持隐藏菜单栏图标", "Hiding menu bar icons isn’t supported on this macOS version"),
                    detail: model.t("自检连续两次发现图标没有真正移出屏幕，已恢复全部显示。", "The self-test found icons were not actually moved off screen twice in a row, so all icons were restored.")) {
                    Button(model.t("打开菜单栏设置", "Open Menu Bar Settings")) { openMenuBarSettings() }
                    Button(model.t("再试一次", "Try Again")) { model.hidingUnavailable = false; model.updateIcon() }
                }
            }
            if model.orderBroken && !model.geometryUnavailable {
                SettingsNotice(tone: .warning, title: model.t("分隔符顺序异常", "Dividers are out of order"),
                    detail: model.t("‹‹ 必须在 MacUtil Bar 图标左边。修复会把三个分隔符恢复到默认位置，图标本身不动。", "‹‹ must sit left of the MacUtil Bar icon. Fixing restores the three dividers to their default positions; your icons stay put.")) {
                    Button(model.t("一键修复", "Fix")) { model.fixOrder() }.buttonStyle(.borderedProminent)
                }
            }
        }
        if !model.error.isEmpty || model.geometryUnavailable || model.hidingUnavailable || (model.orderBroken && !model.geometryUnavailable) {
            notices.padding([.horizontal, .top], SettingsTokens.pagePadding)
        }
    }
}

func openMenuBarSettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
}
