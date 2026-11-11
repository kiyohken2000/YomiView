import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import YomiView

@MainActor
final class FileInformationTests: XCTestCase {
    func testFormatters() {
        XCTAssertEqual(FileInformation.formatSize(0), "0 KB")
        XCTAssertEqual(FileInformation.formatSize(1), "1 KB")
        XCTAssertEqual(FileInformation.formatSize(1024 * 1234), "1,234 KB")
        XCTAssertEqual(FileInformation.formatExposure(0.008), "1/125 秒")
        XCTAssertEqual(FileInformation.formatExposure(2), "2 秒")
        XCTAssertEqual(FileInformation.decoderName("public.jpeg"), "JPEG")
    }

    func testGroupsFromExif() {
        var info = PageFileInfo(fileName: "a.jpg", filePath: "/x/a.jpg", fileSize: 2048)
        info.imageType = "public.jpeg"
        info.imageProperties = [
            kCGImagePropertyPixelWidth as String: 4000,
            kCGImagePropertyPixelHeight as String: 3000,
            kCGImagePropertyDepth as String: 8,
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: "Maker",
                kCGImagePropertyTIFFModel as String: "Model X",
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifFNumber as String: 2.8,
                kCGImagePropertyExifExposureTime as String: 0.004,
                kCGImagePropertyExifISOSpeedRatings as String: [200],
                kCGImagePropertyExifFocalLength as String: 50,
            ],
        ]

        let groups = FileInformation.groups(for: info)
        XCTAssertEqual(groups.map(\.title), ["ファイル", "イメージ", "カメラ"])
        let values = Dictionary(uniqueKeysWithValues: groups.flatMap(\.items).map { ($0.label, $0.value) })
        XCTAssertEqual(values["ファイル名"], "a.jpg")
        XCTAssertEqual(values["サイズ"], "2 KB")
        XCTAssertEqual(values["大きさ"], "4000 x 3000")
        XCTAssertEqual(values["ビットの深さ"], "24")
        XCTAssertEqual(values["デコーダー"], "JPEG")
        XCTAssertEqual(values["カメラ メーカー"], "Maker")
        XCTAssertEqual(values["絞り値"], "f/2.8")
        XCTAssertEqual(values["露出時間"], "1/250 秒")
        XCTAssertEqual(values["ISO 速度"], "ISO-200")
        XCTAssertEqual(values["焦点距離"], "50 mm")
    }

    func testProvidersReturnFileInfo() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YomiViewInfo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let context = CGContext(
            data: nil, width: 30, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let url = dir.appendingPathComponent("1.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let info = try FolderPageProvider(folderURL: dir).fileInfo(at: 0)
        XCTAssertEqual(info.fileName, "1.png")
        XCTAssertNotNil(info.fileSize)
        let values = Dictionary(uniqueKeysWithValues: FileInformation.groups(for: info).flatMap(\.items).map { ($0.label, $0.value) })
        XCTAssertEqual(values["大きさ"], "30 x 20")
        XCTAssertEqual(values["デコーダー"], "PNG")
    }
}

@MainActor
final class BookmarkStoreTests: XCTestCase {
    func testToggleAndPersist() {
        let suite = "YomiViewBookmarkTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = URL(fileURLWithPath: "/tmp/yomiview-books/a.zip")
        let b = URL(fileURLWithPath: "/tmp/yomiview-books/b.zip")

        let store = BookmarkStore(defaults: defaults)
        store.toggle(a)
        store.toggle(b)
        XCTAssertTrue(store.contains(a))
        XCTAssertEqual(BookmarkStore(defaults: defaults).bookmarks.map(\.displayName), ["a.zip", "b.zip"])

        store.toggle(a)
        XCTAssertFalse(store.contains(a))
        store.remove(store.bookmarks[0])
        XCTAssertTrue(BookmarkStore(defaults: defaults).bookmarks.isEmpty)
    }
}
