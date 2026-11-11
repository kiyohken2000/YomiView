import SwiftUI

/// サイドパネルの種類。NeeView の既定の配置（左：本棚・ページリスト・履歴、右：ファイル情報・ナビゲーター・ブックマーク）に合わせる。
enum SidePanelKind: String, CaseIterable, Identifiable {
    case history

    var id: String { rawValue }

    enum Side { case left, right }

    var side: Side {
        switch self {
        case .history: return .left
        }
    }

    var title: String {
        switch self {
        case .history: return "履歴"
        }
    }

    var systemImage: String {
        switch self {
        case .history: return "clock.arrow.circlepath"
        }
    }

    static func panels(on side: Side) -> [SidePanelKind] {
        allCases.filter { $0.side == side }
    }
}

/// 左右のサイドパネルの表示状態。UserDefaults に保存する。
@MainActor
@Observable
final class SidePanelLayout {
    static let shared = SidePanelLayout(defaults: .standard)

    @ObservationIgnored private let defaults: UserDefaults

    var left: SidePanelKind? { didSet { save() } }
    var right: SidePanelKind? { didSet { save() } }
    var leftWidth: CGFloat { didSet { save() } }
    var rightWidth: CGFloat { didSet { save() } }

    static let minWidth: CGFloat = 180
    static let maxWidth: CGFloat = 600

    init(defaults: UserDefaults) {
        self.defaults = defaults
        left = defaults.string(forKey: "panel.left").flatMap(SidePanelKind.init(rawValue:))
        right = defaults.string(forKey: "panel.right").flatMap(SidePanelKind.init(rawValue:))
        leftWidth = defaults.object(forKey: "panel.leftWidth") as? CGFloat ?? 280
        rightWidth = defaults.object(forKey: "panel.rightWidth") as? CGFloat ?? 280
    }

    func selected(on side: SidePanelKind.Side) -> SidePanelKind? {
        side == .left ? left : right
    }

    /// アイコンを押したとき：同じパネルなら閉じ、違うパネルなら切り替える
    func toggle(_ panel: SidePanelKind) {
        switch panel.side {
        case .left: left = left == panel ? nil : panel
        case .right: right = right == panel ? nil : panel
        }
    }

    private func save() {
        defaults.set(left?.rawValue, forKey: "panel.left")
        defaults.set(right?.rawValue, forKey: "panel.right")
        defaults.set(leftWidth, forKey: "panel.leftWidth")
        defaults.set(rightWidth, forKey: "panel.rightWidth")
    }
}

/// サイドパネルのアイコン列（NeeView の SideBar）。選択中のアイコンには外側にアクセント色の線を付ける。
struct SideBarView: View {
    let side: SidePanelKind.Side
    @Bindable var layout: SidePanelLayout

    var body: some View {
        VStack(spacing: 4) {
            ForEach(SidePanelKind.panels(on: side)) { panel in
                let isSelected = layout.selected(on: side) == panel
                Button { layout.toggle(panel) } label: {
                    Image(systemName: panel.systemImage)
                        .font(.system(size: 17))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(isSelected ? Theme.foreground : Theme.grayText)
                        .overlay(alignment: side == .left ? .leading : .trailing) {
                            if isSelected {
                                Rectangle().fill(Theme.accent).frame(width: 3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(panel.title)
            }
            Spacer()
        }
        .padding(.top, 8)
        .frame(width: 40)
        .background(Theme.sideBar)
    }
}

/// サイドパネルの枠。見出しと中身を表示し、内側の端をドラッグして幅を変えられる。
struct SidePanelContainer<Content: View>: View {
    let title: String
    @Binding var width: CGFloat
    let side: SidePanelKind.Side
    @ViewBuilder var content: Content

    @State private var dragStartWidth: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.panelHeader)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)
            content
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
        .overlay(alignment: side == .left ? .trailing : .leading) { splitter }
    }

    private var splitter: some View {
        Rectangle()
            .fill(Theme.sideBar)
            .frame(width: 4)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartWidth ?? width
                        dragStartWidth = start
                        let delta = side == .left ? value.translation.width : -value.translation.width
                        width = min(SidePanelLayout.maxWidth, max(SidePanelLayout.minWidth, start + delta))
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
    }
}
