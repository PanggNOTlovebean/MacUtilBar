import AppKit
import SwiftUI
import MacUtilBarCore

/// Family settings tokens, adapted from MacUtil · Right's `SettingsTokens` (same author, independent copy).
enum SettingsTokens {
    static let spacing: CGFloat = 10
    static let pagePadding: CGFloat = 16
    static let cornerRadius: CGFloat = 10
    static let rowHeight: CGFloat = 38
    static let managedRowHeight: CGFloat = 44
    static let iconSize: CGFloat = 22
    static let iconRadius: CGFloat = 6
    static let border = Color(nsColor: .separatorColor).opacity(0.5)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let titleFont = Font.system(size: 15, weight: .semibold)
    static let bodyFont = Font.system(size: 13)
    static let detailFont = Font.system(size: 12)
    static let versionFont = Font.system(size: 11)
    static let animation = Animation.spring(response: 0.2, dampingFraction: 0.85)
    static let brand = Color(nsColor: BrandColors.dark)
}

enum SettingsLayout {
    static let sidebarWidth: CGFloat = 176
    static let minimumSize = CGSize(width: 760, height: 560)
    static let defaultSize = CGSize(width: 900, height: 660)
}

struct SettingsIconTile: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            .frame(width: SettingsTokens.iconSize, height: SettingsTokens.iconSize)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: SettingsTokens.iconRadius))
    }
}

struct SettingsListRow<Icon: View, Controls: View>: View {
    let title: String
    var detail: String? = nil
    var minHeight: CGFloat = SettingsTokens.rowHeight
    @ViewBuilder var icon: Icon
    @ViewBuilder var controls: Controls
    var body: some View {
        HStack(spacing: SettingsTokens.spacing) {
            icon.frame(width: SettingsTokens.iconSize, height: SettingsTokens.iconSize).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).lineLimit(1).truncationMode(.middle)
                if let detail { Text(detail).font(SettingsTokens.detailFont).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            controls
        }.frame(minHeight: minHeight).contentShape(Rectangle()).accessibilityElement(children: .contain)
    }
}

struct SettingsSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.background(SettingsTokens.surface, in: RoundedRectangle(cornerRadius: SettingsTokens.cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: SettingsTokens.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: SettingsTokens.cornerRadius).stroke(SettingsTokens.border, lineWidth: 0.5))
    }
}

/// A toggle whose label carries a secondary description line (Right's general-page pattern).
struct DescribedToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail).font(SettingsTokens.detailFont).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Inline notice at the top of a page: tinted icon, title, explanation and actions.
struct SettingsNotice<Actions: View>: View {
    enum Tone { case warning, error, info
        var color: Color { switch self { case .warning: return .orange; case .error: return .red; case .info: return .accentColor } }
        var symbol: String { switch self { case .warning: return "exclamationmark.triangle.fill"; case .error: return "xmark.octagon.fill"; case .info: return "info.circle.fill" } }
    }
    let tone: Tone
    let title: String
    let detail: String
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.symbol).foregroundStyle(tone.color).font(.system(size: 15)).frame(width: SettingsTokens.iconSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                // No fixedSize here: notices sit outside a scroll view, where an ideal-height
                // measurement at a narrow proposal can push the whole split view off screen.
                Text(detail).font(SettingsTokens.detailFont).foregroundStyle(.secondary).lineLimit(5).textSelection(.enabled)
                HStack(spacing: 8) { actions }.padding(.top, 4)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: SettingsTokens.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: SettingsTokens.cornerRadius).stroke(tone.color.opacity(0.25), lineWidth: 0.5))
    }
}

/// Paste 1.7.1 style row control: borderless, hover tint, 28pt target, dimmed at the edge.
struct RowIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(hovering && enabled ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(enabled ? .secondary : .quaternary)
            .onHover { hovering = $0 }.help(label).accessibilityLabel(label)
    }
}

struct AppIconImage: View {
    let pid: Int32
    let fallback: String
    var body: some View {
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
        } else {
            SettingsIconTile(symbol: fallback, color: .gray)
        }
    }
}

extension BarSection {
    func title(_ model: AppModel) -> String {
        switch self {
        case .visible: return model.t("常显", "Visible")
        case .hidden: return model.t("隐藏", "Hidden")
        case .alwaysHidden: return model.t("永久隐藏", "Always Hidden")
        }
    }
    func detail(_ model: AppModel) -> String {
        switch self {
        case .visible: return model.t("始终显示在菜单栏", "Always shown in the menu bar")
        case .hidden: return model.t("点击 MacUtil Bar 图标时显示", "Shown when you click MacUtil Bar")
        case .alwaysHidden: return model.t("只在 ⌥ 点击或“显示全部”时显示", "Shown only on ⌥-click or Show All")
        }
    }
    var symbol: String {
        switch self { case .visible: return "eye"; case .hidden: return "eye.slash"; case .alwaysHidden: return "lock" }
    }
    var color: Color {
        switch self { case .visible: return .green; case .hidden: return .blue; case .alwaysHidden: return .gray }
    }
}
