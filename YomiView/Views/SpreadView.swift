import SwiftUI

/// 1〜2ページを高さを揃えて並べ、ストレッチ・拡大・回転・反転・移動を適用して表示する。
/// 大きさと位置の計算は ReaderViewModel.canvas（CanvasLayout）で行い、ここでは描くだけにする。
struct SpreadView: View {
    let canvas: ReaderViewModel.Canvas
    let transform: ViewTransform
    let state: (Int) -> ReaderViewModel.PageState
    var loupeScale: CGFloat?
    var loupeAnchor: UnitPoint = .center

    var body: some View {
        HStack(spacing: 0) {
            ForEach(canvas.pages, id: \.index) { page in
                PageImageView(state: state(page.index))
                    .frame(width: page.size.width, height: page.size.height)
            }
        }
        .frame(width: canvas.frame.width, height: canvas.frame.height)
        .scaleEffect(x: transform.flipHorizontal ? -1 : 1, y: transform.flipVertical ? -1 : 1)
        .scaleEffect(canvas.scale)
        .rotationEffect(.degrees(transform.angle))
        .offset(canvas.offset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // ルーペ：カーソルの位置を中心に拡大する（カーソルを端へ動かすと画像の端が見える）
        .scaleEffect(loupeScale ?? 1, anchor: loupeAnchor)
    }
}

/// 本の表示領域の背景（NeeView の BackgroundType）
struct CanvasBackground: View {
    let type: BackgroundType
    let autoColor: CGColor?

    var body: some View {
        switch type {
        case .black: Color.black
        case .white: Color.white
        case .auto: autoColor.map { Color(cgColor: $0) } ?? Color.black
        case .check: Checkerboard(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0xE0E0E0))
        case .checkDark: Checkerboard(light: Color(hex: 0x202020), dark: Color(hex: 0x000000))
        }
    }
}

private struct Checkerboard: View {
    let light: Color
    let dark: Color
    static let cell: CGFloat = 16

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            let columns = Int(size.width / Self.cell) + 1, rows = Int(size.height / Self.cell) + 1
            var path = Path()
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    path.addRect(CGRect(x: CGFloat(column) * Self.cell, y: CGFloat(row) * Self.cell, width: Self.cell, height: Self.cell))
                }
            }
            context.fill(path, with: .color(dark))
        }
    }
}
