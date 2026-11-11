import SwiftUI

/// 1〜2ページを左右に並べ、高さを揃えてウィンドウに収まるように表示する。
struct SpreadView: View {
    /// 左から並べるページとその状態
    let pages: [(index: Int, state: ReaderViewModel.PageState)]
    var zoomMode: ReaderViewModel.ZoomMode = .fit

    /// 読み込み前・失敗したページの仮の縦横比（幅 / 高さ）。一般的な漫画のページに近い値
    static let placeholderAspect: CGFloat = 0.7

    /// 読み込み前・失敗したページの原寸表示での仮の大きさ
    static let placeholderSize = CGSize(width: 700, height: 1000)

    var body: some View {
        switch zoomMode {
        case .fit: fitted
        case .original: original
        }
    }

    /// ウィンドウに合わせる
    private var fitted: some View {
        GeometryReader { geometry in
            let aspects = pages.map { Self.aspect(of: $0.state) }
            let height = Self.fittedHeight(container: geometry.size, aspects: aspects)
            HStack(spacing: 0) {
                ForEach(Array(zip(pages, aspects)), id: \.0.index) { page, aspect in
                    PageImageView(state: page.state)
                        .frame(width: height * aspect, height: height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// 原寸。ウィンドウより大きければスクロールして見る
    private var original: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                HStack(spacing: 0) {
                    ForEach(pages, id: \.index) { page in
                        let size = Self.originalSize(of: page.state)
                        PageImageView(state: page.state)
                            .frame(width: size.width, height: size.height)
                    }
                }
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
        }
    }

    static func originalSize(of state: ReaderViewModel.PageState) -> CGSize {
        if case .loaded(let image) = state { return image.pointSize }
        return placeholderSize
    }

    static func aspect(of state: ReaderViewModel.PageState) -> CGFloat {
        if case .loaded(let image) = state, image.pointSize.height > 0 {
            return image.pointSize.width / image.pointSize.height
        }
        return placeholderAspect
    }

    /// 並べたページ全体が枠に収まる高さ
    static func fittedHeight(container: CGSize, aspects: [CGFloat]) -> CGFloat {
        let totalAspect = aspects.reduce(0, +)
        guard totalAspect > 0 else { return container.height }
        return max(0, min(container.height, container.width / totalAspect))
    }
}
