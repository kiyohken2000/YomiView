import CoreGraphics
import Foundation
import ImageIO

/// 本のページを提供する。フォルダ / ZIP などの違いはこのプロトコルの実装に閉じ込める。
///
/// 実装はスレッドセーフであること（バックグラウンドから `loadImage` が呼ばれる）。
protocol PageProvider: AnyObject, Sendable {
    /// 本の表示名
    var title: String { get }
    /// 自然順に並んだページ
    var pages: [PageItem] { get }
    /// 指定ページの画像を、長辺が `maxPixelSize` 以下になるよう縮小して読み込む。
    func loadImage(at index: Int, maxPixelSize: Int) throws -> PageImage
    /// 指定ページの元ファイルの情報
    func fileInfo(at index: Int) throws -> PageFileInfo
}

/// 読み込んだページの画像。
struct PageImage: @unchecked Sendable {
    let cgImage: CGImage
    /// 原寸表示のときのサイズ（ポイント）。画像ファイルは元画像のピクセル数、PDF はページのサイズ。
    let pointSize: CGSize

    init(cgImage: CGImage, pointSize: CGSize? = nil) {
        self.cgImage = cgImage
        self.pointSize = pointSize ?? CGSize(width: cgImage.width, height: cgImage.height)
    }

    /// 横長（幅が高さより大きい）か
    var isWide: Bool { pointSize.width > pointSize.height }
}

extension PageProvider {
    var pageCount: Int { pages.count }
}

/// 画像ファイルの判定と、ImageIO による縮小読み込み。
enum ImageLoading {
    /// 対象とする画像の拡張子（小文字）
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff", "heic",
    ]

    static func isImageFileName(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    /// 画像の縁の平均の色（背景「画像に合わせた色」用。NeeView の BackgroundType.Auto）
    static func edgeColor(of image: CGImage) -> CGColor? {
        let size = 16
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var total = [0.0, 0.0, 0.0], count = 0.0
        for y in 0..<size {
            for x in 0..<size where x == 0 || y == 0 || x == size - 1 || y == size - 1 {
                let offset = (y * size + x) * 4
                for c in 0..<3 { total[c] += Double(data[offset + c]) }
                count += 1
            }
        }
        return CGColor(
            colorSpace: space,
            components: [total[0] / count / 255, total[1] / count / 255, total[2] / count / 255, 1]
        )
    }

    /// 元画像の大きさ（ピクセル）。EXIF の向きを反映する。
    static func originalSize(of source: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue,
              let height = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue
        else { return nil }
        let orientation = (props[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// 縮小して読み込み、原寸表示用に元画像の大きさを添える。
    static func loadPage(_ source: CGImageSource, maxPixelSize: Int, name: String) throws -> PageImage {
        let image = try downsample(source, maxPixelSize: maxPixelSize, name: name)
        return PageImage(cgImage: image, pointSize: originalSize(of: source))
    }

    static func loadPage(url: URL, maxPixelSize: Int) throws -> PageImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw BookError.imageDecodeFailed(url.lastPathComponent)
        }
        return try loadPage(source, maxPixelSize: maxPixelSize, name: url.lastPathComponent)
    }

    static func loadPage(data: Data, maxPixelSize: Int, name: String) throws -> PageImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw BookError.imageDecodeFailed(name)
        }
        return try loadPage(source, maxPixelSize: maxPixelSize, name: name)
    }

    /// ImageIO のサムネイル生成で縮小して読み込む。元画像の全体をデコードしない。
    static func downsample(_ source: CGImageSource, maxPixelSize: Int, name: String) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        guard CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            throw BookError.imageDecodeFailed(name)
        }
        return image
    }

    /// 画像の形式とプロパティ（EXIF などを含む）。画像全体はデコードしない。
    static func properties(of source: CGImageSource) -> (type: String?, properties: [String: Any]) {
        let type = CGImageSourceGetType(source) as String?
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        return (type, properties)
    }

    static func downsample(url: URL, maxPixelSize: Int) throws -> CGImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw BookError.imageDecodeFailed(url.lastPathComponent)
        }
        return try downsample(source, maxPixelSize: maxPixelSize, name: url.lastPathComponent)
    }

    static func downsample(data: Data, maxPixelSize: Int, name: String) throws -> CGImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw BookError.imageDecodeFailed(name)
        }
        return try downsample(source, maxPixelSize: maxPixelSize, name: name)
    }
}
