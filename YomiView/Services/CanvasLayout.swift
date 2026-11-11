import CoreGraphics
import Foundation

/// 画像の表示サイズのモード（NeeView/Book/PageStretchMode.cs）。表示名は NeeView の日本語表示。
enum PageStretchMode: String, CaseIterable, Identifiable, Codable {
    case none
    case uniform
    case uniformToFill
    case uniformToSize
    case uniformToVertical
    case uniformToHorizontal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "オリジナル サイズ"
        case .uniform: return "ウィンドウに合わせる"
        case .uniformToFill: return "ウィンドウいっぱいに広げる"
        case .uniformToSize: return "面積をウィンドウに合わせる"
        case .uniformToVertical: return "高さをウィンドウに合わせる"
        case .uniformToHorizontal: return "幅をウィンドウに合わせる"
        }
    }
}

/// 背景（NeeView の BackgroundType。カスタム背景は除く）
enum BackgroundType: String, CaseIterable, Identifiable, Codable {
    case black
    case white
    case auto
    case check
    case checkDark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .black: return "黒色"
        case .white: return "白色"
        case .auto: return "画像に合わせた色"
        case .check: return "白チェック模様"
        case .checkDark: return "黒チェック模様"
        }
    }
}

/// ページを変えたときの表示位置（NeeView の ViewOrigin の「中央または方向依存」）
enum ViewOrigin: Equatable {
    /// 上端・読み始めの側（次のページへ進んだとき）
    case start
    /// 下端・読み終わりの側（スクロールで前のページへ戻ったとき）
    case end
}

/// ユーザーが変えた表示の状態。ページを変えるとリセットする（NeeView の既定）。
struct ViewTransform: Equatable {
    /// ストレッチに掛ける倍率（1 = ストレッチどおり）
    var scale: CGFloat = 1
    /// 回転（度、時計回り）
    var angle: Double = 0
    var flipHorizontal = false
    var flipVertical = false
    var origin: ViewOrigin = .start
    /// 表示位置からの移動量（ポイント）
    var pan: CGSize = .zero

    static let minScale: CGFloat = 0.1
    static let maxScale: CGFloat = 20
}

/// 本の表示領域に1〜2ページを置くときの大きさと位置の計算（NeeView/PageFrames/ContentSizeCalcurator.cs から移植）。
/// 副作用のない関数だけを持つ。
enum CanvasLayout {
    /// ページの大きさを、高さを揃えて横に並べたときの各ページの大きさと全体の大きさ（NeeView の WidePageStretch.UniformHeight）
    static func frame(pageSizes: [CGSize]) -> (sizes: [CGSize], frame: CGSize) {
        let valid = pageSizes.map { $0.width > 0 && $0.height > 0 ? $0 : CGSize(width: 1, height: 1) }
        guard let height = valid.map(\.height).max() else { return ([], .zero) }
        let sizes = valid.map { CGSize(width: $0.width * height / $0.height, height: height) }
        return (sizes, CGSize(width: sizes.map(\.width).reduce(0, +), height: height))
    }

    /// 回転したときに外接する矩形の大きさ
    static func rotatedBounds(_ size: CGSize, angle: Double) -> CGSize {
        let radian = angle * .pi / 180
        let c = abs(cos(radian)), s = abs(sin(radian))
        return CGSize(width: size.width * c + size.height * s, height: size.width * s + size.height * c)
    }

    /// ストレッチの倍率。`allowScaleUp` / `allowScaleDown` で 1 倍を越える拡大・下回る縮小を制限する。
    static func stretchScale(
        mode: PageStretchMode, frame: CGSize, angle: Double, canvas: CGSize,
        allowScaleUp: Bool = true, allowScaleDown: Bool = true
    ) -> CGFloat {
        guard frame.width > 0, frame.height > 0, canvas.width > 0, canvas.height > 0 else { return 1 }
        func allow(_ scale: CGFloat) -> CGFloat {
            var scale = scale
            if !allowScaleUp { scale = min(scale, 1) }
            if !allowScaleDown { scale = max(scale, 1) }
            return scale
        }
        let bounds = rotatedBounds(frame, angle: angle)
        let scaleX = allow(canvas.width / bounds.width)
        let scaleY = allow(canvas.height / bounds.height)
        switch mode {
        case .none: return 1
        case .uniform: return min(scaleX, scaleY)
        case .uniformToFill: return max(scaleX, scaleY)
        case .uniformToHorizontal: return scaleX
        case .uniformToVertical: return scaleY
        case .uniformToSize:
            return allow(sqrt((canvas.width * canvas.height) / (frame.width * frame.height)))
        }
    }

    /// 表示位置（ページを変えたときの位置）。はみ出す方向だけ、上端 / 下端と読む向きの端に寄せる。
    static func originOffset(content: CGSize, canvas: CGSize, origin: ViewOrigin, direction: ReadingDirection) -> CGSize {
        let overX = max(0, (content.width - canvas.width) / 2)
        let overY = max(0, (content.height - canvas.height) / 2)
        // 右開きの読み始めは右端（内容を左へずらす）
        let startX = direction == .rightToLeft ? -overX : overX
        switch origin {
        case .start: return CGSize(width: startX, height: overY)
        case .end: return CGSize(width: -startX, height: -overY)
        }
    }

    /// 内容が表示領域から離れすぎないよう移動量を制限する。はみ出さない方向は中央に固定。
    static func clampOffset(_ offset: CGSize, content: CGSize, canvas: CGSize) -> CGSize {
        let overX = max(0, (content.width - canvas.width) / 2)
        let overY = max(0, (content.height - canvas.height) / 2)
        return CGSize(width: min(overX, max(-overX, offset.width)), height: min(overY, max(-overY, offset.height)))
    }
}
