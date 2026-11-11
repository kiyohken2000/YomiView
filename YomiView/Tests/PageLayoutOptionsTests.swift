import CoreGraphics
import XCTest
@testable import YomiView

/// phase-13：最後のページを単独表示、横長ページの分割、ページの並び順、サブフォルダーの読み込み。
final class SpreadOptionsTests: XCTestCase {
    private func pages(_ spreads: [Spread]) -> [[Int]] { spreads.map(\.pages) }

    func testLastPageSingle() {
        var options = SpreadCalculator.Options()
        options.lastSingle = true
        // 表紙単独 + 残り4ページ：最後の 4 は 3 と組まない
        XCTAssertEqual(pages(SpreadCalculator.spreads(pageCount: 5, mode: .spread, options: options)), [[0], [1, 2], [3], [4]])
        // もともと最後が余るときは変わらない
        XCTAssertEqual(pages(SpreadCalculator.spreads(pageCount: 4, mode: .spread, options: options)), [[0], [1, 2], [3]])
        // 1ページ表示には影響しない
        XCTAssertEqual(pages(SpreadCalculator.spreads(pageCount: 3, mode: .single, options: options)), [[0], [1], [2]])
    }

    func testLastPageSingleWithoutCover() {
        let options = SpreadCalculator.Options(coverSingle: false, landscapeSingle: true, lastSingle: true)
        XCTAssertEqual(pages(SpreadCalculator.spreads(pageCount: 4, mode: .spread, options: options)), [[0, 1], [2], [3]])
    }

    func testDividePageOnlyInSingleMode() {
        var options = SpreadCalculator.Options()
        options.dividePage = true
        let single = SpreadCalculator.spreads(pageCount: 3, mode: .single, options: options, isWide: { $0 == 1 })
        XCTAssertEqual(single, [
            Spread(pages: [0]), Spread(pages: [1], part: .first), Spread(pages: [1], part: .second), Spread(pages: [2]),
        ])
        let spread = SpreadCalculator.spreads(pageCount: 3, mode: .spread, options: options, isWide: { $0 == 1 })
        XCTAssertTrue(spread.allSatisfy { $0.part == nil })
    }

    func testSpreadIndexChoosesPart() {
        let spreads = [Spread(pages: [0], part: .first), Spread(pages: [0], part: .second), Spread(pages: [1])]
        XCTAssertEqual(SpreadCalculator.spreadIndex(containing: 0, in: spreads), 0)
        XCTAssertEqual(SpreadCalculator.spreadIndex(containing: 0, part: .second, in: spreads), 1)
        // 分割されていないページは part に関係なく見つかる
        XCTAssertEqual(SpreadCalculator.spreadIndex(containing: 1, part: .second, in: spreads), 2)
    }

    func testPartSideFollowsReadingDirection() {
        XCTAssertEqual(PagePart.first.side(direction: .rightToLeft), .right)
        XCTAssertEqual(PagePart.second.side(direction: .rightToLeft), .left)
        XCTAssertEqual(PagePart.first.side(direction: .leftToRight), .left)
        XCTAssertEqual(PagePart.second.side(direction: .leftToRight), .right)
    }
}

final class PageSorterTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private var items: [PageItem] {
        [
            PageItem(index: 0, name: "a2.png", kind: .file(URL(fileURLWithPath: "/a2.png")), entryIndex: 2,
                     modificationDate: base.addingTimeInterval(30), fileSize: 300),
            PageItem(index: 1, name: "a10.jpg", kind: .file(URL(fileURLWithPath: "/a10.jpg")), entryIndex: 0,
                     modificationDate: base.addingTimeInterval(10), fileSize: 100),
            PageItem(index: 2, name: "b1.png", kind: .file(URL(fileURLWithPath: "/b1.png")), entryIndex: 1,
                     modificationDate: base.addingTimeInterval(10), fileSize: 200),
        ]
    }

    private func names(_ mode: PageSortMode, seed: UInt64 = 0) -> [String] {
        PageSorter.sorted(items, mode: mode, seed: seed).map(\.name)
    }

    func testSortModes() {
        XCTAssertEqual(names(.fileName), ["a2.png", "a10.jpg", "b1.png"])
        XCTAssertEqual(names(.fileNameDescending), ["b1.png", "a10.jpg", "a2.png"])
        XCTAssertEqual(names(.fileType), ["a10.jpg", "a2.png", "b1.png"])
        XCTAssertEqual(names(.fileTypeDescending), ["a2.png", "b1.png", "a10.jpg"])
        // 同じ日付は名前順
        XCTAssertEqual(names(.timeStamp), ["a10.jpg", "b1.png", "a2.png"])
        XCTAssertEqual(names(.timeStampDescending), ["a2.png", "a10.jpg", "b1.png"])
        XCTAssertEqual(names(.size), ["a10.jpg", "b1.png", "a2.png"])
        XCTAssertEqual(names(.sizeDescending), ["a2.png", "b1.png", "a10.jpg"])
        XCTAssertEqual(names(.entry), ["a10.jpg", "b1.png", "a2.png"])
        XCTAssertEqual(names(.entryDescending), ["a2.png", "b1.png", "a10.jpg"])
    }

    func testRandomIsDeterministicForSeedAndKeepsAllPages() {
        XCTAssertEqual(names(.random, seed: 42), names(.random, seed: 42))
        XCTAssertEqual(Set(names(.random, seed: 7)), Set(items.map(\.name)))
    }

    func testSortedProviderMapsIndices() throws {
        let provider = SortedPageProvider(base: FakeProvider(count: 5), mode: .fileNameDescending)
        XCTAssertEqual(provider.pages.map(\.name), ["4.png", "3.png", "2.png", "1.png", "0.png"])
        XCTAssertEqual(provider.pages.map(\.index), [0, 1, 2, 3, 4])
        // FakeProvider は元のページ番号 + 1 を幅にする
        XCTAssertEqual(try provider.loadImage(at: 0, maxPixelSize: 10).cgImage.width, 5)
        XCTAssertEqual(try provider.fileInfo(at: 1).fileName, "3.png")
        XCTAssertThrowsError(try provider.loadImage(at: 5, maxPixelSize: 10))
    }
}

final class RecursiveFolderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YomiViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func touch(_ path: String) throws {
        let url = tempDir.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    func testRecursiveFolderIncludesSubfoldersByPath() throws {
        for path in ["book/2.png", "book/10.png", "book/sub2/1.png", "book/sub10/1.png", "book/.hidden/1.png",
                     "book/sub2/.x.png", "book/sub2/a.txt"] {
            try touch(path)
        }
        let folder = tempDir.appendingPathComponent("book", isDirectory: true)

        XCTAssertEqual(try FolderPageProvider(folderURL: folder).pages.map(\.name), ["2.png", "10.png"])
        let recursive = try FolderPageProvider(folderURL: folder, recursive: true)
        XCTAssertTrue(recursive.isRecursive)
        XCTAssertEqual(recursive.pages.map(\.name), ["2.png", "10.png", "sub2/1.png", "sub10/1.png"])
        XCTAssertTrue(recursive.pages.allSatisfy { $0.fileSize == 1 && $0.modificationDate != nil })
    }

    func testRecursiveFolderWithImagesOnlyInSubfolders() throws {
        try touch("book/sub/1.png")
        let folder = tempDir.appendingPathComponent("book", isDirectory: true)
        XCTAssertThrowsError(try FolderPageProvider(folderURL: folder))
        XCTAssertEqual(try FolderPageProvider(folderURL: folder, recursive: true).pages.count, 1)
    }
}

@MainActor
final class PageLayoutViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "YomiViewTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeViewModel(direction: ReadingDirection = .rightToLeft) -> ReaderViewModel {
        let settings = AppSettings(defaults: defaults)
        settings.readingDirection = direction
        return ReaderViewModel(settings: settings, recentBooks: RecentBooksStore(defaults: defaults))
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("条件を満たさない")
    }

    func testNewSettingsDefaults() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.lastSingle)
        XCTAssertFalse(settings.dividePage)
        XCTAssertEqual(settings.pageSortMode, .fileName)
        XCTAssertFalse(settings.isRecursiveFolder)
        settings.pageSortMode = .size
        settings.dividePage = true
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.pageSortMode, .size)
        XCTAssertTrue(reloaded.dividePage)
    }

    func testDividedWidePageIsReadInTwoHalves() async {
        let viewModel = makeViewModel(direction: .rightToLeft)
        viewModel.settings.dividePage = true
        viewModel.manualViewMode = .single
        viewModel.updateContainerSize(CGSize(width: 800, height: 600))
        viewModel.setProvider(FakeProvider(count: 3, widePages: [1]))
        viewModel.goNext()
        await waitUntil { viewModel.widePages[1] == true }

        // 右開きでは右半分から読む
        XCTAssertEqual(viewModel.currentSpread, Spread(pages: [1], part: .first))
        XCTAssertEqual(viewModel.canvas.pages.map(\.half), [.right])
        XCTAssertEqual(viewModel.canvas.pages.first?.size.width ?? 0, 100, accuracy: 0.01)

        viewModel.goNext()
        XCTAssertEqual(viewModel.currentIndex, 1)
        XCTAssertEqual(viewModel.currentSpread, Spread(pages: [1], part: .second))
        XCTAssertEqual(viewModel.canvas.pages.map(\.half), [.left])

        viewModel.goNext()
        XCTAssertEqual(viewModel.currentIndex, 2)
        XCTAssertNil(viewModel.currentPart)

        // 戻ると後半から
        viewModel.goPrevious()
        XCTAssertEqual(viewModel.currentSpread, Spread(pages: [1], part: .second))
        viewModel.goPrevious()
        XCTAssertEqual(viewModel.currentSpread, Spread(pages: [1], part: .first))
        viewModel.goPrevious()
        XCTAssertEqual(viewModel.currentIndex, 0)
    }

    func testPageSortKeepsCurrentPage() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 5))
        viewModel.go(to: 1)

        viewModel.setPageSortMode(.fileNameDescending)
        XCTAssertEqual(viewModel.appliedSortMode, .fileNameDescending)
        XCTAssertEqual(viewModel.provider?.pages.map(\.name), ["4.png", "3.png", "2.png", "1.png", "0.png"])
        // 表示していた 1.png を表示し続ける
        XCTAssertEqual(viewModel.currentIndex, 3)
        XCTAssertEqual(viewModel.provider?.pages[viewModel.currentIndex].name, "1.png")

        // 名前↑ に戻すと元の並び
        viewModel.setPageSortMode(.fileName)
        XCTAssertEqual(viewModel.provider?.pages.map(\.name), ["0.png", "1.png", "2.png", "3.png", "4.png"])
        XCTAssertEqual(viewModel.currentIndex, 1)

        // 変わっていなければ何もしない
        let before = viewModel.provider
        viewModel.applyPageSort()
        XCTAssertTrue(viewModel.provider === before)
    }

    func testSetProviderAppliesSortSetting() {
        let viewModel = makeViewModel()
        viewModel.settings.pageSortMode = .entryDescending
        viewModel.setProvider(FakeProvider(count: 3))
        XCTAssertEqual(viewModel.provider?.pages.map(\.name), ["2.png", "1.png", "0.png"])
    }
}
