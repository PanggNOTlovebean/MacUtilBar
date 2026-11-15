import SwiftUI
import ServiceManagement
import MacUtilBarCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0
    @State private var recording = false
    @State private var keyMonitor: Any?
    init(model: AppModel, initialTab: Int = 0) { self.model = model; _tab = State(initialValue: initialTab) }
    func t(_ zh: String, _ en: String) -> String { model.t(zh, en) }
    func binding<T>(_ path: WritableKeyPath<Configuration, T>) -> Binding<T> {
        Binding(get: { model.config[keyPath: path] }, set: { value in model.save { $0[keyPath: path] = value } })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ZStack { RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [Color(red: 0.64, green: 0.48, blue: 1), Color(red: 0.42, green: 0.25, blue: 0.84)], startPoint: .topLeading, endPoint: .bottomTrailing)); Image(systemName: "menubar.rectangle").font(.system(size: 32)).foregroundStyle(.white) }.frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) { Text("MacUtil Bar").font(.system(size: 24, weight: .bold)); Text(t("菜单栏，只留需要的。", "Keep only what you need in the menu bar.")).foregroundStyle(.secondary) }
                Spacer(); Text(Version.current).font(.caption).foregroundStyle(.secondary)
            }.padding(24)
            HStack(spacing: 24) {
                ForEach(0..<2) { index in
                    Button { tab = index } label: {
                        VStack(spacing: 10) { Text(index == 0 ? t("基本设置", "General") : t("布局", "Layout")).frame(width: 100); Rectangle().fill(tab == index ? Color.accentColor : .clear).frame(height: 2) }
                    }.frame(width: 100).buttonStyle(.plain).foregroundStyle(tab == index ? Color.accentColor : Color.secondary).keyboardShortcut(index == 0 ? "1" : "2", modifiers: .command)
                }; Spacer()
            }.padding(.horizontal, 24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !model.error.isEmpty { Text(t("配置或操作有误，保留上次有效设置：", "Previous settings preserved: ") + model.error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    if model.geometryUnavailable {
                        Text(t("尚未确认菜单栏图标位置，已暂停收起。请在系统设置 → 菜单栏检查是否允许 MacUtil Bar 显示，再从访达打开应用。", "The icon position could not be verified. Hiding is paused. Check that MacUtil Bar is allowed in System Settings → Menu Bar, then open the app from Finder.")).font(.caption).foregroundStyle(.orange)
                        Button(t("打开系统菜单栏设置", "Open Menu Bar Settings")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!) }
                        Button(t("重新检查", "Retry")) { model.retryGeometry() }
                    }
                    if tab == 0 { general } else { layout }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Button { NSWorkspace.shared.activateFileViewerSelecting([model.file.url]) } label: {
                HStack { Text(t("配置文件：", "Configuration: ") + model.file.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")); Spacer() }.font(.system(size: 11)).foregroundStyle(.secondary).padding(12)
            }.buttonStyle(.plain)
        }.background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { stopRecording() }
    }
    func title(_ zh: String, _ en: String) -> some View { Text(t(zh, en)).font(.system(size: 15, weight: .semibold)) }
    func row<C: View>(_ zh: String, _ en: String, @ViewBuilder control: () -> C) -> some View {
        VStack(spacing: 0) { HStack(spacing: 12) { Text(t(zh, en)).font(.system(size: 13)); Spacer(minLength: 12); control().frame(width: 220, alignment: .trailing) }.frame(minHeight: 44); Divider() }
    }
    func toggle(_ zh: String, _ en: String, _ path: WritableKeyPath<Configuration, Bool>) -> some View { row(zh, en) { Toggle(t(zh, en), isOn: binding(path)).labelsHidden().toggleStyle(.switch).controlSize(.small) } }
    var general: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("常规", "General")
            row("快捷键", "Shortcut") {
                HStack { Button(recording ? t("请按快捷键…", "Press shortcut…") : (model.config.shortcut.isEmpty ? t("录制快捷键", "Record shortcut") : model.config.shortcut)) { record() }; Button(t("清除", "Clear")) { model.save { $0.shortcut = "" } } }
            }
            if model.shortcutFailed { Text(t("该快捷键无法注册，可能已被占用", "Shortcut unavailable; it may be in use.")).font(.caption).foregroundStyle(.red) }
            row("界面语言", "Language") { Picker("", selection: binding(\.language)) { Text("跟随系统 / System").tag("system"); Text("简体中文").tag("zh-Hans"); Text("English").tag("en") }.labelsHidden() }
            row("外观", "Appearance") { Picker("", selection: binding(\.appearance)) { Text(t("系统", "System")).tag("system"); Text(t("浅色", "Light")).tag("light"); Text(t("深色", "Dark")).tag("dark") }.pickerStyle(.segmented).labelsHidden() }
            row("开机启动", "Launch at login") { Toggle("", isOn: Binding(get: { SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval }, set: model.setLogin)).labelsHidden().toggleStyle(.switch).controlSize(.small) }
            if SMAppService.mainApp.status == .requiresApproval { Button(t("需要批准 · 打开登录项设置", "Approval required · Open Login Items")) { SMAppService.openSystemSettingsLoginItems() }.padding(.vertical, 8) }
            title("展开与收起", "Reveal & collapse").padding(.top, 22)
            toggle("悬停在菜单栏空白处展开", "Reveal on empty-space hover", \.hover)
            row("悬停延迟", "Hover delay") { Stepper(String(format: "%.1f s", Double(model.config.hoverDelay) / 1000), value: binding(\.hoverDelay), in: 100...3000, step: 100).disabled(!model.config.hover) }
            toggle("在菜单栏上滚动展开", "Scroll to reveal", \.scroll)
            row("自动收起", "Auto-collapse") { Picker("", selection: binding(\.autoCollapse)) { ForEach(Array(Set([0,5,10,15,30,60,model.config.autoCollapse])).sorted(), id: \.self) { Text($0 == 0 ? t("关闭", "Off") : "\($0) s").tag($0) } }.labelsHidden() }
            toggle("切换应用时收起", "Collapse on app switch", \.collapseOnSwitch)
            Text(t("左键点击展开或收起；⌥ 点击显示全部。", "Click to toggle; Option-click to show all.")).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 10)
            title("外观", "Appearance").padding(.top, 22)
            row("分隔符样式", "Divider style") { Picker("", selection: binding(\.divider)) { Text(t("箭头", "Arrow")).tag("chevron"); Text(t("竖线", "Line")).tag("line"); Text(t("圆点", "Dot")).tag("dot") }.pickerStyle(.segmented).labelsHidden() }
            if NSScreen.screens.contains(where: { $0.safeAreaInsets.top > 0 }) { toggle("刘海遮挡提示", "Notch indicator", \.notchBadge) }
        }
    }
    var layout: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("当前分区", "Current sections")
            HStack(spacing: 0) {
                ForEach(0..<3) { i in
                    VStack { Text([t("永久隐藏 ┆", "Always hidden ┆"),t("隐藏 ◉", "Hidden ◉"),t("常显 ｜ 系统", "Visible | System")][i]).frame(maxWidth: .infinity).frame(height: 36).background(Color.primary.opacity(Double(3-i) * 0.035)); Text(model.hasCountSample && !model.geometryUnavailable ? "\(model.counts[i])" : "—").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Text(t("数量为全部展开时采样的窗口数，包含系统图标。", "Counts are window samples from Show All, including system icons.")).font(.caption).foregroundStyle(.secondary)
            HStack { Button(t("显示全部", "Show All")) { model.setState(.all) }; Button(t("收起", "Collapse")) { model.setState(.collapsed) } }
            title("移动图标", "Move icons")
            Text(t("按住 ⌘ 把图标拖到 ◉ 左边、紧邻的空白分隔符左侧即可收起。\n拖到 ┆ 左边则永久隐藏，⌥ 点击 ◉ 时才显示。", "⌘-drag icons left of ◉ and its adjacent spacer to hide them.\nDrag left of ┆ to keep them hidden until Option-click." )).font(.system(size: 13)).lineSpacing(6)
            if model.orderBroken || model.hidingUnavailable || model.notchCount > 0 || model.visibleRemainder > 0 {
                title("状态", "Status")
                if model.visibleRemainder > 0 { Text(t("收起后仍有 \(model.visibleRemainder) 个窗口可见；系统指示器可能保持显示。", "\(model.visibleRemainder) windows remain visible after collapse; system indicators may stay visible.")).font(.caption).foregroundStyle(.secondary) }
                if model.orderBroken { HStack { Text(t("分隔符顺序异常", "Dividers are out of order")); Spacer(); Button(t("一键修复", "Fix")) { model.fixOrder() } } }
                if model.hidingUnavailable { Text(t("隐藏自检失败，已恢复展开。当前系统或分隔符布局无法安全隐藏图标。", "Hiding self-test failed. Icons were restored; check the divider layout or system support.")).foregroundStyle(.red); Button(t("打开系统菜单栏设置", "Open Menu Bar Settings")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!) } }
                if model.notchCount > 0 { HStack { Text(t("有 \(model.notchCount) 个窗口可能被刘海遮挡", "\(model.notchCount) windows may be obscured by the notch")); Spacer(); Button(t("展开查看", "Reveal")) { model.setState(.all); let token = model.generation; DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if model.generation == token { model.setState(.collapsed) } } } } }
            }
            title("可视化排序", "Visual arrangement")
            HStack { Text(t("识别并调整每个图标，需要辅助功能权限。", "Identifying and arranging individual icons requires Accessibility.")).font(.system(size: 13)); Spacer(); Button(t("即将推出", "Coming later")) {}.disabled(true) }
            Text(t("1.0 不申请辅助功能或录屏权限。", "Version 1.0 requests no Accessibility or Screen Recording permission.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    func stopRecording() { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; keyMonitor = nil; recording = false; model.shortcutFailed = !model.hotkey.register(model.config.shortcut) }
    func record() {
        stopRecording(); recording = true; _ = model.hotkey.register("")
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopRecording(); return nil }
            guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1 else { return nil }
            var parts: [String] = []
            for (flag, name) in [(NSEvent.ModifierFlags.control,"ctrl"),(.option,"option"),(.shift,"shift"),(.command,"cmd")] { if event.modifierFlags.contains(flag) { parts.append(name) } }
            let value = (parts + [key]).joined(separator: "+")
            if Shortcut.parse(value) != nil { model.save { $0.shortcut = value }; stopRecording() }
            return nil
        }
    }
}
