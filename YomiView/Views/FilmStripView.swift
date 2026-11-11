import SwiftUI

/// フィルムストリップ（NeeView/PageSelect/FilmStrip）。ページのサムネイルを横に並べ、クリックでそのページへ移動する。
/// 並びの向きはページスライダーと同じく本の開き方向に合わせる。
struct FilmStripView: View {
    let viewModel: ReaderViewModel

    /// NeeView の既定のサムネイルの幅
    static let imageWidth: CGFloat = 96

    var body: some View {
        let current = Set(viewModel.currentSpread?.pages ?? [])
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<viewModel.pageCount, id: \.self) { page in
                        FilmStripItem(
                            store: viewModel.pageThumbnails,
                            page: page,
                            isSelected: current.contains(page)
                        ) {
                            viewModel.go(to: page)
                        }
                        .id(page)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: viewModel.currentSpread?.first) { _, page in
                if let page { withAnimation { proxy.scrollTo(page, anchor: .center) } }
            }
            .onAppear {
                if let page = viewModel.currentSpread?.first { proxy.scrollTo(page, anchor: .center) }
            }
        }
        // 右開きでは右端を1ページ目にする（画像は反転しない）
        .environment(\.layoutDirection, viewModel.readingDirection == .rightToLeft ? .rightToLeft : .leftToRight)
        .frame(height: Self.imageWidth + 20)
        .background(Theme.bottomBar)
    }
}

private struct FilmStripItem: View {
    let store: ThumbnailStore<Int>
    let page: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 2) {
            ThumbnailView(store: store, key: page)
                .frame(width: FilmStripView.imageWidth, height: FilmStripView.imageWidth)
            Rectangle()
                .fill(isSelected ? Theme.selectedMark : .clear)
                .frame(height: 4)
        }
        .padding(2)
        .background(isSelected ? Color.white.opacity(0.15) : (isHovered ? Theme.itemMouseOver : .clear))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
        .help("\(page + 1)")
    }
}
