import AppKit
import SwiftUI
import MacUtilBarCore

struct IconsPage: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionStrip(model: model)
            if model.axTrusted { itemList } else { ScrollView { VStack(alignment: .leading, spacing: 12) { permissionCard; manualCard }.frame(maxWidth: .infinity, alignment: .leading) } }
        }
        .padding(SettingsTokens.pagePadding)
        .onAppear { model.itemConsumers += 1; model.scanItems() }
        .onDisappear { model.itemConsumers -= 1 }
    }

    // MARK: Without Accessibility
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsListRow(title: model.t("需要辅助功能权限", "Accessibility permission required"),
                            detail: nil, minHeight: SettingsTokens.managedRowHeight) {
                SettingsIconTile(symbol: "hand.raised.fill", color: .blue)
            } controls: {
                Button(model.t("打开系统设置…", "Open System Settings…")) { Accessibility.request() }
                    .accessibilityIdentifier("icons.accessibility.request")
            }
            Text(model.t("用来识别每个图标属于哪个 App、在这里直接移动它们，以及搜索并点开图标。MacUtil Bar 不读取你输入的内容。授权后自动刷新，无需重启。",
                         "Used to identify which app owns each icon, move icons from here, and search and open them. MacUtil Bar never reads what you type. Refreshes automatically once granted."))
                .font(SettingsTokens.detailFont).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.leading, SettingsTokens.iconSize + SettingsTokens.spacing).padding(.bottom, 12)
        }.padding(.horizontal, 12).modifier(SettingsSurface())
    }
    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.t("不授权也可以手动整理", "Arrange by hand without permission")).font(SettingsTokens.titleFont)
            VStack(spacing: 0) {
                instruction("command", .purple, model.t("按住 ⌘ 把图标拖到 MacUtil Bar 图标左边", "Hold ⌘ and drag an icon left of the MacUtil Bar icon"),
                            model.t("点击 MacUtil Bar 图标即可收起这些图标", "Click the MacUtil Bar icon to collapse them"))
                Divider().padding(.leading, SettingsTokens.iconSize + 22)
                instruction("chevron.left.2", .gray, model.t("拖到 ‹‹ 左边则永久隐藏", "Drag left of ‹‹ to keep it always hidden"),
                            model.t("只在 ⌥ 点击或“显示全部”时出现", "Shown only on ⌥-click or Show All"))
                Divider().padding(.leading, SettingsTokens.iconSize + 22)
                instruction("arrow.uturn.backward", .green, model.t("退出 MacUtil Bar 会恢复所有图标", "Quitting MacUtil Bar restores every icon"),
                            model.t("隐藏只是把图标推出屏幕，不会改动其他 App", "Hiding only pushes icons off screen; other apps are untouched"))
            }.padding(.horizontal, 12).modifier(SettingsSurface())
        }
    }
    private func instruction(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        SettingsListRow(title: title, detail: detail, minHeight: SettingsTokens.managedRowHeight) { SettingsIconTile(symbol: symbol, color: color) } controls: { EmptyView() }
    }

    // MARK: With Accessibility
    private var itemList: some View {
        let groups = model.grouped
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(model.t("筛选图标", "Filter icons"), text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Spacer()
                Button { model.search.show() } label: { Label(model.t("搜索面板", "Search Panel"), systemImage: "magnifyingglass") }
                    .help(model.config.searchShortcut.isEmpty ? model.t("可在“展开与收起”中设置快捷键", "Set a shortcut in Reveal & Collapse") : Shortcut.display(model.config.searchShortcut))
                Button { model.scanItems() } label: { Image(systemName: "arrow.clockwise") }.help(model.t("重新识别", "Rescan"))
            }
            List {
                ForEach(BarSection.allCases) { section in
                    let rows = ItemLayout.filter(groups[section] ?? [], query: query)
                    SwiftUI.Section {
                        if rows.isEmpty {
                            Text(query.isEmpty ? model.t("没有图标", "No icons") : model.t("没有匹配的图标", "No matching icons"))
                                .font(SettingsTokens.detailFont).foregroundStyle(.tertiary).frame(minHeight: 30)
                        }
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                            ItemRow(model: model, item: item, section: section, canMoveUp: index > 0 && query.isEmpty, canMoveDown: index < rows.count - 1 && query.isEmpty)
                                .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Image(systemName: section.symbol).foregroundStyle(section.color).frame(width: 16)
                            Text(section.title(model)).font(.system(size: 12, weight: .semibold))
                            Text("\(groups[section]?.count ?? 0)").font(SettingsTokens.detailFont).foregroundStyle(.secondary)
                            Text("· " + section.detail(model)).font(SettingsTokens.detailFont).foregroundStyle(.tertiary).lineLimit(1)
                        }.padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.plain).environment(\.defaultMinListRowHeight, SettingsTokens.managedRowHeight)
            .modifier(SettingsSurface())
            .overlay { if !model.itemsLoaded { ProgressView() } }
            .accessibilityIdentifier("icons.list")
            Text(model.t("移动会临时显示全部图标，并替你按住 ⌘ 拖动；完成后按实际位置确认。被刘海挡住的图标需先手动拖出。",
                         "Moving briefly shows all icons and ⌘-drags for you, then confirms from the real positions. Icons behind the notch must first be dragged out by hand."))
                .font(SettingsTokens.detailFont).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

struct ItemRow: View {
    @ObservedObject var model: AppModel
    let item: MenuBarItem
    let section: BarSection
    let canMoveUp: Bool
    let canMoveDown: Bool
    var body: some View {
        let busy = model.moving != nil
        VStack(alignment: .leading, spacing: 2) {
            SettingsListRow(title: item.displayName, detail: item.detail, minHeight: SettingsTokens.managedRowHeight) {
                AppIconImage(pid: item.pid, fallback: "app.dashed")
            } controls: {
                if model.moving == item.id { ProgressView().controlSize(.small) }
                Picker(model.t("分区", "Section"), selection: Binding(get: { section }, set: { model.move(item.id, to: $0) })) {
                    ForEach(BarSection.allCases) { Text($0.title(model)).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
                RowIconButton(symbol: "arrow.up", label: model.t("向左移动", "Move left")) { model.move(item.id, by: -1) }.disabled(!canMoveUp || busy)
                RowIconButton(symbol: "arrow.down", label: model.t("向右移动", "Move right")) { model.move(item.id, by: 1) }.disabled(!canMoveDown || busy)
            }
            .disabled(busy || !model.canMove)
            .contextMenu { Button(model.t("打开它的菜单", "Open Its Menu")) { model.press(item.id) } }
            if let error = model.moveErrors[item.id] {
                HStack(spacing: 6) {
                    Text(error).font(SettingsTokens.detailFont).foregroundStyle(.red)
                    Button(model.t("关闭", "Dismiss")) { model.moveErrors[item.id] = nil }.buttonStyle(.link).font(SettingsTokens.detailFont)
                }.padding(.leading, SettingsTokens.iconSize + SettingsTokens.spacing).padding(.bottom, 6)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.displayName), \(section.title(model))")
    }
}

/// Menu-bar-like strip: Always hidden ‹‹ Hidden ◉ Visible | System, with counts.
struct SectionStrip: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let counts = model.sectionCounts
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                segment(.alwaysHidden, counts, opacity: 0.09)
                segment(.hidden, counts, opacity: 0.05).overlay(alignment: .leading) { marker(model.config.divider == "line" ? "│" : model.config.divider == "dot" ? "•" : "‹‹").offset(x: -14) }
                segment(.visible, counts, opacity: 0.015).overlay(alignment: .leading) { marker(nil).offset(x: -14) }
            }
            .frame(height: 52)
            .modifier(SettingsSurface())
            Text(caption).font(SettingsTokens.detailFont).foregroundStyle(.secondary).lineLimit(2)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("icons.sections")
    }
    private var caption: String {
        if model.geometryUnavailable { return model.t("尚未确认图标位置，数量显示为“—”。", "Icon positions are unverified, so counts show “—”.") }
        if model.axTrusted { return model.t("数量来自辅助功能识别，不含 MacUtil Bar 自己的分隔符。", "Counts come from Accessibility and exclude MacUtil Bar’s own dividers.") }
        if model.visibleRemainder > 0 { return model.t("收起后仍有 \(model.visibleRemainder) 个窗口可见；系统指示器可能保持显示。", "\(model.visibleRemainder) windows stay visible after collapsing; system indicators may remain.") }
        return model.t("数量为“全部显示”时采样的窗口数，包含系统图标。", "Counts are window samples taken while showing all, including system icons.")
    }
    private func segment(_ section: BarSection, _ counts: [BarSection: Int]?, opacity: Double) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: section.symbol).font(.system(size: 11)).foregroundStyle(section.color)
                Text(section.title(model)).font(.system(size: 12, weight: .medium))
            }
            Text(counts.map { "\($0[section] ?? 0)" } ?? "—").font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(opacity))
    }
    private func marker(_ glyph: String?) -> some View {
        ZStack {
            Rectangle().fill(SettingsTokens.border).frame(width: 0.5).frame(maxHeight: .infinity)
            Group {
                if let glyph { Text(glyph).font(.system(size: 11, weight: .semibold)) }
                else { Image(nsImage: barIcon(expanded: model.state != .collapsed, badge: false, failed: false)) }
            }
            .frame(width: 24, height: 20).background(SettingsTokens.surface, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(SettingsTokens.border, lineWidth: 0.5))
            .foregroundStyle(.secondary)
        }.frame(width: 28)
    }
}
