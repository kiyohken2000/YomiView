import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
import ZIPFoundation
@testable import YomiView

final class PageProviderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YomiViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - テスト用データ

    /// 単色の PNG データを作る。
    private func pngData(width: Int = 40, height: Int = 60) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    private func makeZip(named name: String, entries: [String: Data]) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }

    // MARK: - フォルダ

    func testFolderListsOnlyDirectImagesInNaturalOrder() throws {
        let folder = tempDir.appendingPathComponent("book", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = try pngData()
        for name in ["page10.png", "page2.png", "page1.JPG", ".hidden.png", "readme.txt"] {
            try png.write(to: folder.appendingPathComponent(name))
        }
        let sub = folder.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try png.write(to: sub.appendingPathComponent("page0.png"))

        let provider = try FolderPageProvider(folderURL: folder)

        XCTAssertEqual(provider.title, "book")
        XCTAssertEqual(provider.pages.map(\.name), ["page1.JPG", "page2.png", "page10.png"])
        XCTAssertEqual(provider.pages.map(\.index), [0, 1, 2])
    }

    func testFolderLoadsImage() throws {
        let folder = tempDir.appendingPathComponent("book", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try pngData(width: 40, height: 60).write(to: folder.appendingPathComponent("1.png"))

        let provider = try FolderPageProvider(folderURL: folder)
        let image = try provider.loadImage(at: 0, maxPixelSize: 1000).cgImage
        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 60)
    }

    func testFolderWithoutImagesThrows() throws {
        let folder = tempDir.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("text".utf8).write(to: folder.appendingPathComponent("a.txt"))

        XCTAssertThrowsError(try FolderPageProvider(folderURL: folder)) { error in
            XCTAssertEqual(error as? BookError, .noImages("empty"))
        }
    }

    func testBrokenImageFailsOnlyThatPage() throws {
        let folder = tempDir.appendingPathComponent("book", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try pngData().write(to: folder.appendingPathComponent("1.png"))
        try Data("not an image".utf8).write(to: folder.appendingPathComponent("2.png"))

        let provider = try FolderPageProvider(folderURL: folder)
        XCTAssertEqual(provider.pageCount, 2)
        XCTAssertNoThrow(try provider.loadImage(at: 0, maxPixelSize: 100))
        XCTAssertThrowsError(try provider.loadImage(at: 1, maxPixelSize: 100))
        XCTAssertThrowsError(try provider.loadImage(at: 2, maxPixelSize: 100)) { error in
            XCTAssertEqual(error as? BookError, .pageOutOfRange(2))
        }
    }

    // MARK: - ZIP / CBZ

    func testZipExcludesMacOSXAndHiddenEntriesAndSortsNaturally() throws {
        let png = try pngData()
        let url = try makeZip(named: "comic.zip", entries: [
            "page10.png": png,
            "page2.png": png,
            "page1.png": png,
            "__MACOSX/._page1.png": png,
            "__MACOSX/page3.png": png,
            ".hidden.png": png,
            ".git/obj.png": png,
            "notes.txt": Data("x".utf8),
        ])

        let provider = try ZipPageProvider(archiveURL: url)

        XCTAssertEqual(provider.title, "comic")
        XCTAssertEqual(provider.pages.map(\.name), ["page1.png", "page2.png", "page10.png"])
    }

    func testZipIncludesImagesInSubfoldersOrderedByPath() throws {
        let png = try pngData()
        let url = try makeZip(named: "vols.cbz", entries: [
            "vol2/1.png": png,
            "vol10/1.png": png,
            "vol1/2.png": png,
            "vol1/10.png": png,
        ])

        let provider = try ZipPageProvider(archiveURL: url)

        XCTAssertEqual(
            provider.pages.map(\.kind),
            ["vol1/2.png", "vol1/10.png", "vol2/1.png", "vol10/1.png"].map { .archiveEntry(path: $0) }
        )
    }

    func testZipLoadsDownsampledImage() throws {
        let url = try makeZip(named: "big.zip", entries: ["1.png": try pngData(width: 400, height: 800)])

        let provider = try ZipPageProvider(archiveURL: url)
        let image = try provider.loadImage(at: 0, maxPixelSize: 100).cgImage

        XCTAssertEqual(max(image.width, image.height), 100)
        XCTAssertEqual(image.width, 50)
    }

    func testZipWithoutImagesThrows() throws {
        let url = try makeZip(named: "text.zip", entries: ["a.txt": Data("x".utf8)])
        XCTAssertThrowsError(try ZipPageProvider(archiveURL: url)) { error in
            XCTAssertEqual(error as? BookError, .noImages("text.zip"))
        }
    }

    func testBrokenZipThrows() throws {
        let url = tempDir.appendingPathComponent("broken.zip")
        try Data("this is not a zip file".utf8).write(to: url)
        XCTAssertThrowsError(try ZipPageProvider(archiveURL: url)) { error in
            XCTAssertEqual(error as? BookError, .unreadableArchive("broken.zip"))
        }
    }

    func testZipConcurrentLoadsAreSafe() throws {
        let png = try pngData()
        var entries: [String: Data] = [:]
        for i in 1...20 { entries["\(i).png"] = png }
        let provider = try ZipPageProvider(archiveURL: try makeZip(named: "many.zip", entries: entries))

        let failures = Counter()
        DispatchQueue.concurrentPerform(iterations: 40) { i in
            if (try? provider.loadImage(at: i % 20, maxPixelSize: 50)) == nil {
                failures.increment()
            }
        }
        XCTAssertEqual(failures.value, 0)
    }

    func testEntryPathFilter() {
        XCTAssertTrue(ZipPageProvider.isPageEntryPath("a/b/001.webp"))
        XCTAssertTrue(ZipPageProvider.isPageEntryPath("001.HEIC"))
        XCTAssertFalse(ZipPageProvider.isPageEntryPath("__MACOSX/a/001.jpg"))
        XCTAssertFalse(ZipPageProvider.isPageEntryPath("a/._001.jpg"))
        XCTAssertFalse(ZipPageProvider.isPageEntryPath(".thumbs/001.jpg"))
        XCTAssertFalse(ZipPageProvider.isPageEntryPath("a/001.txt"))
        XCTAssertFalse(ZipPageProvider.isPageEntryPath("a/"))
    }

    // MARK: - 本の種類の判定

    func testBookSourceDetection() throws {
        let folder = tempDir.appendingPathComponent("f", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let zip = tempDir.appendingPathComponent("a.ZIP")
        let cbz = tempDir.appendingPathComponent("b.cbz")
        let txt = tempDir.appendingPathComponent("c.txt")
        for url in [zip, cbz, txt] { try Data().write(to: url) }

        XCTAssertEqual(try BookSource.detect(folder), .folder(folder))
        XCTAssertEqual(try BookSource.detect(zip), .archive(zip))
        XCTAssertEqual(try BookSource.detect(cbz), .archive(cbz))
        XCTAssertThrowsError(try BookSource.detect(txt)) { error in
            XCTAssertEqual(error as? BookError, .unsupportedFormat("c.txt"))
        }
        XCTAssertThrowsError(try BookSource.detect(tempDir.appendingPathComponent("missing.zip"))) { error in
            XCTAssertEqual(error as? BookError, .notFound("missing.zip"))
        }
    }
}

/// concurrentPerform 内で失敗回数を数えるための小さなカウンタ。
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
