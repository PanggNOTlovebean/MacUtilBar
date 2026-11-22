import AppKit
import SwiftUI
import MacUtilBarCore
import ServiceManagement

extension AppModel {
    func binding<T>(_ path: WritableKeyPath<Configuration, T>) -> Binding<T> {
        Binding(get: { self.config[keyPath: path] }, set: { value in withAnimation(SettingsTokens.animation) { self.save { $0[keyPath: path] = value } } })
    }
}

// MARK: Reveal & Collapse
struct RevealPage: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            SwiftUI.Section(model.t("快捷键", "Shortcuts")) {
                LabeledContent(model.t("收起 / 展开", "Collapse / Reveal")) {
                    ShortcutField(model: model, path: \.shortcut, slot: .toggle).accessibilityIdentifier("reveal.shortcut")
                }
                if model.shortcutFailed { failure }
                LabeledContent {
                    ShortcutField(model: model, path: \.searchShortcut, slot: .search).accessibilityIdentifier("reveal.searchShortcut")
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.t("搜索菜单栏图标", "Search menu bar icons"))
                        Text(model.t("需要辅助功能权限；默认不设置", "Requires Accessibility; unset by default")).font(SettingsTokens.detailFont).foregroundStyle(.secondary)
                    }
                }
                if model.searchShortcutFailed { failure }
            }
            SwiftUI.Section {
                DescribedToggle(title: model.t("悬停在菜单栏空白处展开", "Reveal on hover over empty menu bar space"),
                                detail: model.t("指针停在图标左侧的空白处时展开，离开菜单栏后开始自动收起计时", "Reveal when the pointer rests in the empty space left of your icons"), isOn: model.binding(\.hover))
                    .accessibilityIdentifier("reveal.hover")
                LabeledContent(model.t("悬停延迟", "Hover delay")) {
                    Stepper(value: model.binding(\.hoverDelay), in: 100...3000, step: 100) {
                        Text(String(format: "%.1f ", Double(model.config.hoverDelay) / 1000) + model.t("秒", "s")).monospacedDigit()
                    }.fixedSize()
                }.disabled(!model.config.hover)
                DescribedToggle(title: model.t("在菜单栏上滚动展开", "Scroll on the menu bar"),
                                detail: model.t("向下滚动展开，向上滚动收起", "Scroll down to reveal, up to collapse"), isOn: model.binding(\.scroll))
                    .accessibilityIdentifier("reveal.scroll")
            } header: { Text(model.t("展开方式", "Reveal")) } footer: {
                Text(model.t("左键点击 MacUtil Bar 图标始终可以展开或收起；⌥ 点击显示全部；右键打开菜单。", "Clicking the MacUtil Bar icon always toggles; ⌥-click shows all; right-click opens the menu."))
                    .font(SettingsTokens.detailFont).foregroundStyle(.secondary)
            }
            SwiftUI.Section(model.t("自动收起", "Auto-collapse")) {
                Picker(model.t("展开后自动收起", "Collapse after"), selection: model.binding(\.autoCollapse)) {
                    ForEach(Array(Set([0, 5, 10, 15, 30, 60, model.config.autoCollapse])).sorted(), id: \.self) {
                        Text($0 == 0 ? model.t("不自动收起", "Never") : model.t("\($0) 秒", "\($0) seconds")).tag($0)
                    }
                }.accessibilityIdentifier("reveal.autoCollapse")
                DescribedToggle(title: model.t("切换应用时收起", "Collapse when switching apps"),
                                detail: model.t("前台 App 改变时立即收起", "Collapse as soon as the frontmost app changes"), isOn: model.binding(\.collapseOnSwitch))
                Text(model.t("指针停在菜单栏上、或任何菜单打开时，计时暂停。", "The timer pauses while the pointer is on the menu bar or a menu is open."))
                    .font(SettingsTokens.detailFont).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var failure: some View {
        Text(model.t("该快捷键无法注册，可能已被其他应用占用", "This shortcut couldn’t be registered; another app may be using it"))
            .font(SettingsTokens.detailFont).foregroundStyle(.red)
    }
}

// MARK: Appearance
struct AppearancePage: View {
    @ObservedObject var model: AppModel
    @State private var draft: Double = Double(SpacingPreference.systemDefault)
    @State private var confirmApply = false
    @State private var confirmReset = false
    var body: some View {
        Form {
            SwiftUI.Section(model.t("分隔符", "Divider")) {
                Picker(model.t("永久隐藏分隔符样式", "Always-hidden divider"), selection: model.binding(\.divider)) {
                    Text(model.t("箭头 ‹‹", "Arrow ‹‹")).tag("chevron")
                    Text(model.t("竖线 │", "Line │")).tag("line")
                    Text(model.t("圆点 •", "Dot •")).tag("dot")
                }.pickerStyle(.segmented).accessibilityIdentifier("appearance.divider")
                Text(model.t("只在“显示全部”时可见，收起后被推出屏幕。", "Only visible while showing all; pushed off screen otherwise."))
                    .font(SettingsTokens.detailFont).foregroundStyle(.secondary)
            }
            if model.hasNotch {
                SwiftUI.Section(model.t("刘海", "Notch")) {
                    DescribedToggle(title: model.t("刘海遮挡提示", "Notch indicator"),
                                    detail: model.notchCount > 0 ? model.t("当前约有 \(model.notchCount) 个图标被刘海挡住", "About \(model.notchCount) icons are behind the notch now") : model.t("有图标被刘海挡住时，在 MacUtil Bar 图标右上角显示小圆点", "Show a dot on the MacUtil Bar icon when icons are behind the notch"),
                                    isOn: model.binding(\.notchBadge))
                    if model.notchCount > 0 {
                        LabeledContent(model.t("把它们收进隐藏区，或减小下方的图标间距。", "Move them into the hidden section, or reduce icon spacing below.")) {
                            Button(model.t("整理图标…", "Arrange Icons…")) { model.page = .icons }
                        }.font(SettingsTokens.detailFont)
                    }
                }
            }
            SwiftUI.Section {
                LabeledContent(model.t("图标间距", "Icon spacing")) {
                    HStack(spacing: 10) {
                        Slider(value: $draft, in: Double(SpacingPreference.range.lowerBound)...Double(SpacingPreference.range.upperBound), step: 1).frame(width: 180)
                            .accessibilityIdentifier("appearance.spacing")
                        Text("\(Int(draft)) pt").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                SpacingPreview(spacing: draft)
                LabeledContent(model.t("系统当前值", "Current system value")) {
                    Text(model.spacing.map { "\($0) pt" } ?? model.t("默认（约 16 pt）", "Default (about 16 pt)")).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button(model.t("恢复默认", "Restore Default")) { confirmReset = true }.disabled(model.spacing == nil)
                    Button(model.t("应用…", "Apply…")) { confirmApply = true }.buttonStyle(.borderedProminent)
                        .disabled(model.spacing == Int(draft) || (model.spacing == nil && Int(draft) == SpacingPreference.systemDefault))
                }
            } header: { Text(model.t("图标间距", "Icon Spacing")) } footer: {
                Text(model.t("写入系统全局偏好，之后打开的 App 才会使用新间距；已运行的 App 需要重新打开，或注销后重新登录。MacUtil Bar 不会替你退出其他 App。",
                             "Writes a system-wide preference. Apps opened afterwards use it; running apps need to be reopened, or log out and back in. MacUtil Bar never quits other apps for you."))
                    .font(SettingsTokens.detailFont).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { draft = Double(model.spacing ?? SpacingPreference.systemDefault) }
        .confirmationDialog(model.t("把菜单栏图标间距改为 \(Int(draft)) pt？", "Set menu bar icon spacing to \(Int(draft)) pt?"), isPresented: $confirmApply) {
            Button(model.t("应用", "Apply")) { model.applySpacing(Int(draft)) }
            Button(model.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(model.t("修改会写入系统全局偏好。之后打开的应用才会使用新的间距，已经在运行的应用需要重新打开，或者注销重新登录。", "This writes a system-wide preference. Apps opened afterwards use the new spacing; running apps must be reopened, or log out and back in."))
        }
        .confirmationDialog(model.t("恢复系统默认间距？", "Restore the default spacing?"), isPresented: $confirmReset) {
            Button(model.t("恢复默认", "Restore Default")) { model.applySpacing(nil); draft = Double(SpacingPreference.systemDefault) }
            Button(model.t("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(model.t("删除 MacUtil Bar 写入的间距偏好。同样只对之后打开的 App 生效。", "Removes the spacing preference. Again, only apps opened afterwards are affected."))
        }
    }
}

struct SpacingPreview: View {
    let spacing: Double
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(index == 2 ? 0.55 : 0.3)).frame(width: 16, height: 14)
            }
        }
        .animation(SettingsTokens.animation, value: spacing)
        .frame(maxWidth: .infinity).frame(height: 28)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

// MARK: General
struct GeneralPage: View {
    @ObservedObject var model: AppModel
    @State private var confirmReset = false
    var body: some View {
        Form {
            SwiftUI.Section(model.t("界面", "Interface")) {
                Picker(model.t("语言", "Language"), selection: model.binding(\.language)) {
                    Text(model.t("跟随系统", "System")).tag("system"); Text("简体中文").tag("zh-Hans"); Text("English").tag("en")
                }.accessibilityIdentifier("settings.language")
                Picker(model.t("外观", "Appearance"), selection: model.binding(\.appearance)) {
                    Text(model.t("跟随系统", "System")).tag("system"); Text(model.t("浅色", "Light")).tag("light"); Text(model.t("深色", "Dark")).tag("dark")
                }.accessibilityIdentifier("settings.appearance")
            }
            SwiftUI.Section(model.t("启动", "Startup")) {
                Toggle(model.t("登录时启动", "Launch at Login"), isOn: Binding(get: { model.loginState == .on || model.loginState == .needsApproval }, set: model.setLogin))
                    .disabled(model.loginBusy).accessibilityIdentifier("settings.launchAtLogin")
                switch model.loginState {
                case .needsApproval:
                    LabeledContent(model.t("等待系统批准。请在登录项中允许 MacUtil Bar。", "Approval pending. Allow MacUtil Bar in Login Items.")) {
                        Button(model.t("打开登录项设置…", "Open Login Items…")) { SMAppServiceOpener.open() }
                    }.font(SettingsTokens.detailFont)
                case .unavailable:
                    Text(model.t("系统没有找到本 App 的登录服务。请从“应用程序”文件夹打开 MacUtil Bar 后再开启。", "The system can’t find this app’s login service. Open MacUtil Bar from the Applications folder, then turn this on.")).font(SettingsTokens.detailFont).foregroundStyle(.secondary)
                default:
                    Text(model.t("默认关闭。以系统实际注册状态为准。", "Off by default. Shows the system’s actual registration.")).font(SettingsTokens.detailFont).foregroundStyle(.secondary)
                }
                if let error = model.loginError { Text(error).font(SettingsTokens.detailFont).foregroundStyle(.red).textSelection(.enabled) }
            }
            SwiftUI.Section { UpdateCheckView(english: model.isEnglish) }
            SwiftUI.Section(model.t("配置文件", "Configuration File")) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.t("当前配置", "Current configuration")).font(.system(size: 13, weight: .medium))
                    Text(model.file.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(SettingsTokens.detailFont).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text(model.t("可直接编辑，保存后自动生效；格式有误时保留上次的有效设置。", "Edit it directly; changes apply on save. Invalid edits keep the last valid settings."))
                    .font(SettingsTokens.detailFont).foregroundStyle(.secondary)
                HStack {
                    Button(model.t("打开配置文件", "Open Config File")) { NSWorkspace.shared.open(model.file.url) }
                    Button(model.t("在访达中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([model.file.url]) }
                    Spacer()
                }
            }
            SwiftUI.Section {
                HStack {
                    Button(model.t("恢复默认设置…", "Reset Settings…")) { confirmReset = true }
                    Spacer()
                    Button(model.t("退出 MacUtil Bar", "Quit MacUtil Bar")) { NSApp.terminate(nil) }
                }
                Text(model.t("退出时恢复所有图标。MacUtil Bar 不读取或修改其他 MacUtil 应用的配置。", "Quitting restores every icon. MacUtil Bar never reads or changes other MacUtil apps’ settings."))
                    .font(SettingsTokens.detailFont).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(model.t("恢复默认设置？登录项和系统图标间距保持不变。", "Reset settings? Login item and system icon spacing stay unchanged."), isPresented: $confirmReset) {
            Button(model.t("恢复默认", "Reset"), role: .destructive) {
                let login = model.config.launchAtLogin
                model.save { $0 = Configuration(); $0.launchAtLogin = login }
            }
            Button(model.t("取消", "Cancel"), role: .cancel) {}
        }
    }
}

enum SMAppServiceOpener { static func open() { SMAppService.openSystemSettingsLoginItems() } }

// MARK: Shortcut recorder
struct ShortcutField: View {
    @ObservedObject var model: AppModel
    let path: WritableKeyPath<Configuration, String>
    let slot: HotKeys.Slot
    @State private var recording = false
    @State private var monitor: Any?
    var body: some View {
        let value = model.config[keyPath: path]
        HStack(spacing: 4) {
            Button(action: { recording ? stop() : start() }) {
                Text(recording ? model.t("请按快捷键…", "Type shortcut…") : value.isEmpty ? model.t("点击录制", "Record") : Shortcut.display(value))
                    .font(.system(size: 12, weight: value.isEmpty || recording ? .regular : .medium)).monospaced(!value.isEmpty && !recording)
                    .foregroundStyle(recording ? Color.accentColor : value.isEmpty ? .secondary : .primary)
                    .frame(minWidth: 96).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(recording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(recording ? Color.accentColor : SettingsTokens.border, lineWidth: recording ? 1 : 0.5))
            }.buttonStyle(.plain)
            if !value.isEmpty && !recording {
                RowIconButton(symbol: "xmark.circle.fill", label: model.t("清除", "Clear")) { model.save { $0[keyPath: path] = "" } }
            }
        }.onDisappear { stop() }
    }
    private func start() {
        stop(); recording = true
        model.hotkeys.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1 else { return nil }
            var parts: [String] = []
            for (flag, name) in [(NSEvent.ModifierFlags.control, "ctrl"), (.option, "option"), (.shift, "shift"), (.command, "cmd")] where event.modifierFlags.contains(flag) { parts.append(name) }
            let value = (parts + [key]).joined(separator: "+")
            if Shortcut.parse(value) != nil, HotKeys.keyCodes[key] != nil { model.save { $0[keyPath: path] = value }; stop() }
            else { NSSound.beep() }
            return nil
        }
    }
    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { recording = false; model.applyConfig() }
    }
}
