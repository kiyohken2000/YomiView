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
    func loadImage(at index: Int, maxPixelSize: Int) throws -> CGImage
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
