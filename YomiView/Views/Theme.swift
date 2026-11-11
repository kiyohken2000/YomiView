import SwiftUI

/// NeeView のダークテーマ（NeeView/Libraries/Themes/DarkTheme.json）の配色。
enum Theme {
    static let windowBackground = Color(hex: 0x000000)
    static let foreground = Color(hex: 0xF0F0F0)
    static let grayText = Color(hex: 0x909090)
    static let accent = Color(hex: 0x1188DD)

    /// アドレスバー（MenuBar.Background）
    static let menuBar = Color(hex: 0x383838)
    /// アドレス欄（MenuBar.Address.Background）
    static let address = Color(hex: 0x282828)
    /// サイドパネルのアイコン列（SideBar.Background）
    static let sideBar = Color(hex: 0x303030)
    /// サイドパネル（Panel.Background）
    static let panel = Color(hex: 0x202020)
    static let panelHeader = Color(hex: 0x808080)
    static let panelSeparator = Color(hex: 0x404040)
    /// ページスライダー・フィルムストリップ（BottomBar.Background）
    static let bottomBar = Color(hex: 0x383838)
    static let sliderBackground = Color(hex: 0x505050)
    static let textBoxBackground = Color(hex: 0x202020)
    static let textBoxBorder = Color(hex: 0xA0A0A0)

    static let itemMouseOver = accent.opacity(0.15)
    static let itemSelected = accent.opacity(0.25)
    static let buttonMouseOver = Color.white.opacity(0x44 / 255)
    static let thumbnailBackground = Color(hex: 0x404040)
    static let thumbnailForeground = Color(hex: 0x808080)
    static let selectedMark = Color(hex: 0xFFA500)
    static let bookmarkIcon = Color(hex: 0xFFA500)
    static let notificationBackground = Color.black.opacity(0x88 / 255)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// NeeView のアイコンボタン。マウスを乗せると背景と枠が付く。
struct IconButtonStyle: ButtonStyle {
    /// アイコンの色（アドレスバーは文字色、パネル内はアクセント色）
    var foreground: Color = Theme.accent
    var isChecked = false

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, foreground: foreground, isChecked: isChecked)
    }

    private struct IconButtonBody: View {
        let configuration: Configuration
        let foreground: Color
        let isChecked: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? foreground : foreground.opacity(0.3))
                .frame(minWidth: 28, minHeight: 28)
                .background(background)
                .overlay {
                    if isEnabled, isHovered || isChecked {
                        Rectangle().strokeBorder(Theme.accent.opacity(isChecked ? 1 : 0.65), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }

        private var background: Color {
            guard isEnabled else { return .clear }
            if configuration.isPressed { return Theme.accent.opacity(0.25) }
            if isChecked { return Theme.accent.opacity(0.25) }
            return isHovered ? Theme.itemMouseOver : .clear
        }
    }
}
