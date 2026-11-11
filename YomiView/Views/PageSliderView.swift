import SwiftUI

/// ウィンドウ下部のページスライダー（NeeView/PageSelect/PageSlider）。
/// 右開きではスライダーの向きを反転する（NeeView の既定「本の開き方向に合わせる」）。
struct PageSliderView: View {
    let pageCount: Int
    let currentPage: Int
    let isReversed: Bool
    let onSelect: (Int) -> Void

    @State private var isEditing = false
    @State private var editingText = ""
    @FocusState private var isTextFocused: Bool

    static let thumbSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 8) {
            slider
            indexText
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(Theme.bottomBar)
    }

    private var maxIndex: Int { max(0, pageCount - 1) }

    private var slider: some View {
        GeometryReader { geometry in
            let usable = max(1, geometry.size.width - Self.thumbSize)
            let ratio = maxIndex > 0 ? CGFloat(currentPage) / CGFloat(maxIndex) : 0
            let position = (isReversed ? 1 - ratio : ratio) * usable
            let center = Self.thumbSize / 2
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Theme.sliderBackground)
                    .frame(height: 2)
                    .padding(.horizontal, center)
                // 先頭側（スライダーの始点からつまみまで）をアクセント色にする
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: isReversed ? usable - position : position, height: 2)
                    .offset(x: isReversed ? position + center : center)
                Circle()
                    .strokeBorder(Theme.accent, lineWidth: 2.5)
                    .background(Circle().fill(Theme.bottomBar))
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .offset(x: position)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard pageCount > 0 else { return }
                        let raw = min(1, max(0, (value.location.x - center) / usable))
                        let page = Int(((isReversed ? 1 - raw : raw) * CGFloat(maxIndex)).rounded())
                        if page != currentPage { onSelect(page) }
                    }
            )
        }
    }

    @ViewBuilder
    private var indexText: some View {
        if isEditing {
            TextField("", text: $editingText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 50)
                .focused($isTextFocused)
                .onSubmit {
                    if let number = Int(editingText.trimmingCharacters(in: .whitespaces)), pageCount > 0 {
                        onSelect(min(max(1, number), pageCount) - 1)
                    }
                    isEditing = false
                }
                .onExitCommand { isEditing = false }
                .onChange(of: isTextFocused) { _, focused in if !focused { isEditing = false } }
                .foregroundStyle(Theme.foreground)
        } else {
            Text(pageCount > 0 ? "\(currentPage + 1) / \(pageCount)" : "")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Theme.foreground)
                .frame(minWidth: 50, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard pageCount > 0 else { return }
                    editingText = "\(currentPage + 1)"
                    isEditing = true
                    isTextFocused = true
                }
                .help("クリックしてページ番号を入力")
        }
    }
}
