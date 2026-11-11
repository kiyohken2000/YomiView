import SwiftUI

/// 1〜2ページを左右に並べ、高さを揃えてウィンドウに収まるように表示する。
struct SpreadView: View {
    /// 左から並べるページとその状態
    let pages: [(index: Int, state: ReaderViewModel.PageState)]

    /// 読み込み前・失敗したページの仮の縦横比（幅 / 高さ）。一般的な漫画のページに近い値
    static let placeholderAspect: CGFloat = 0.7

    var body: some View {
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
