import Foundation
import ImageIO

/// ファイル情報パネルの表示内容を作る（NeeView/SidePanels/FileInfo の項目と日本語名を移植）。
///
/// NeeView の項目のうち、macOS の ImageIO で取得できるものを、ファイル・イメージ・ソース・カメラ・GPS の各グループに分けて並べる。
/// 値のない項目は表示しない。
enum FileInformation {
    struct Item: Equatable, Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    struct Group: Equatable, Identifiable {
        let title: String
        let items: [Item]
        var id: String { title }
    }

    static func groups(for info: PageFileInfo) -> [Group] {
        let exif = info.imageProperties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = info.imageProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let gps = info.imageProperties[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        let props = info.imageProperties

        let file: [Item?] = [
            item("ファイル名", info.fileName),
            item("ファイル パス", info.filePath),
            item("作成日時", info.creationDate.map(formatDate)),
            item("更新日時", info.modificationDate.map(formatDate)),
            item("サイズ", info.fileSize.map(formatSize)),
            item("アーカイブ パス", info.archivePath),
            item("アーカイバー", info.archiver),
        ]

        var dimensions: String?
        if let size = info.pdfPageSize {
            dimensions = "\(Int(size.width.rounded())) x \(Int(size.height.rounded())) pt"
        } else if let w = number(props[kCGImagePropertyPixelWidth as String]),
                  let h = number(props[kCGImagePropertyPixelHeight as String]) {
            dimensions = "\(Int(w)) x \(Int(h))"
        }
        let image: [Item?] = [
            item("大きさ", dimensions),
            item("水平方向の解像度", number(props[kCGImagePropertyDPIWidth as String]).map { "\(format($0)) dpi" }),
            item("垂直方向の解像度", number(props[kCGImagePropertyDPIHeight as String]).map { "\(format($0)) dpi" }),
            item("ビットの深さ", bitDepth(props)),
            item("デコーダー", info.imageType.map(decoderName)),
        ]

        let origin: [Item?] = [
            item("作成者", tiff[kCGImagePropertyTIFFArtist as String] as? String),
            item("撮影日時", exif[kCGImagePropertyExifDateTimeOriginal as String] as? String),
            item("プログラム名", tiff[kCGImagePropertyTIFFSoftware as String] as? String),
            item("著作権", tiff[kCGImagePropertyTIFFCopyright as String] as? String),
        ]

        let camera: [Item?] = [
            item("カメラ メーカー", tiff[kCGImagePropertyTIFFMake as String] as? String),
            item("カメラ モデル", tiff[kCGImagePropertyTIFFModel as String] as? String),
            item("絞り値", number(exif[kCGImagePropertyExifFNumber as String]).map { "f/\(format($0))" }),
            item("露出時間", number(exif[kCGImagePropertyExifExposureTime as String]).map(formatExposure)),
            item("ISO 速度", (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first.map { "ISO-\($0)" }),
            item("露出補正", number(exif[kCGImagePropertyExifExposureBiasValue as String]).map { "\(format($0)) ステップ" }),
            item("焦点距離", number(exif[kCGImagePropertyExifFocalLength as String]).map { "\(format($0)) mm" }),
            item("35mm 焦点距離", number(exif[kCGImagePropertyExifFocalLenIn35mmFilm as String]).map { "\(Int($0)) mm" }),
            item("レンズ モデル", exif[kCGImagePropertyExifLensModel as String] as? String),
        ]

        let location: [Item?] = [
            item("緯度", gpsCoordinate(gps, value: kCGImagePropertyGPSLatitude, ref: kCGImagePropertyGPSLatitudeRef)),
            item("経度", gpsCoordinate(gps, value: kCGImagePropertyGPSLongitude, ref: kCGImagePropertyGPSLongitudeRef)),
            item("高度", number(gps[kCGImagePropertyGPSAltitude as String]).map { "\(format($0)) m" }),
        ]

        return [
            ("ファイル", file), ("イメージ", image), ("ソース", origin), ("カメラ", camera), ("GPS", location),
        ].compactMap { title, items in
            let items = items.compactMap { $0 }
            return items.isEmpty ? nil : Group(title: title, items: items)
        }
    }

    // MARK: - 書式

    private static func item(_ label: String, _ value: String?) -> Item? {
        guard let value, !value.isEmpty else { return nil }
        return Item(label: label, value: value)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// NeeView と同じく KB 単位で表示（例：1,234 KB）
    static func formatSize(_ bytes: Int64) -> String {
        let kb = (bytes + 1023) / 1024
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: kb)) ?? "\(kb)") KB"
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func formatExposure(_ seconds: Double) -> String {
        if seconds > 0, seconds < 1 {
            return "1/\(Int((1 / seconds).rounded())) 秒"
        }
        return "\(format(seconds)) 秒"
    }

    private static func bitDepth(_ props: [String: Any]) -> String? {
        guard let depth = number(props[kCGImagePropertyDepth as String]) else { return nil }
        let hasAlpha = props[kCGImagePropertyHasAlpha as String] as? Bool ?? false
        let isGray = (props[kCGImagePropertyColorModel as String] as? String) == (kCGImagePropertyColorModelGray as String)
        let channels = isGray ? 1 : 3
        return "\(Int(depth) * (channels + (hasAlpha ? 1 : 0)))"
    }

    static func decoderName(_ uti: String) -> String {
        switch uti {
        case "public.jpeg": return "JPEG"
        case "public.png": return "PNG"
        case "com.compuserve.gif": return "GIF"
        case "org.webmproject.webp": return "WebP"
        case "com.microsoft.bmp": return "BMP"
        case "public.tiff": return "TIFF"
        case "public.heic", "public.heif": return "HEIF"
        default: return uti
        }
    }

    private static func gpsCoordinate(_ gps: [String: Any], value: CFString, ref: CFString) -> String? {
        guard let degrees = number(gps[value as String]) else { return nil }
        let reference = gps[ref as String] as? String ?? ""
        return String(format: "%.6f° %@", degrees, reference)
    }
}
