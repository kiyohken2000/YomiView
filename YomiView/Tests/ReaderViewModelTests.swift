import CoreGraphics
import XCTest
@testable import YomiView

/// ページ番号 + 1 を幅に入れた画像を返すテスト用 Provider。`widePages` のページは横長にする。
final class FakeProvider: PageProvider, @unchecked Sendable {
    let title = "fake"
    let pages: [PageItem]
    let failingIndex: Int?
    let widePages: Set<Int>

    init(count: Int, failingIndex: Int? = nil, widePages: Set<Int> = []) {
        pages = (0..<count).map { PageItem(index: $0, name: "\($0).png", kind: .archiveEntry(path: "\($0).png")) }
        self.failingIndex = failingIndex
        self.widePages = widePages
    }

    func fileInfo(at index: Int) throws -> PageFileInfo {
        PageFileInfo(fileName: pages[index].name, filePath: pages[index].name)
    }

    func loadImage(at index: Int, maxPixelSize: Int) throws -> PageImage {
        if index == failingIndex { throw BookError.imageDecodeFailed(pages[index].name) }
        let context = CGContext(
            data: nil, width: index + 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let size = widePages.contains(index) ? CGSize(width: 200, height: 100) : CGSize(width: 70, height: 100)
        return PageImage(cgImage: context.makeImage()!, pointSize: size)
    }
}

@MainActor
final class ReaderViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "YomiViewTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeViewModel(direction: ReadingDirection = .leftToRight) -> ReaderViewModel {
        let settings = AppSettings(defaults: defaults)
        settings.readingDirection = direction
        return ReaderViewModel(settings: settings, recentBooks: RecentBooksStore(defaults: defaults))
    }

    private func waitForLoads(_ viewModel: ReaderViewModel) async {
        for _ in 0..<400 {
            if viewModel.displayedPages.allSatisfy({ viewModel.state(of: $0) != .loading }) { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("ページの読み込みが終わらない")
    }

    private func loadedWidth(_ viewModel: ReaderViewModel, page: Int) -> Int? {
        if case .loaded(let image) = viewModel.state(of: page) { return image.cgImage.width }
        return nil
    }

    // MARK: - 1ページ表示

    func testNavigationStaysWithinBook() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 3))
        XCTAssertEqual(viewModel.currentIndex, 0)
        XCTAssertEqual(viewModel.windowTitle, "fake (1 / 3) - 0.png")

        viewModel.goPrevious()
        XCTAssertEqual(viewModel.currentIndex, 0)

        viewModel.goNext()
        viewModel.goNext()
        XCTAssertEqual(viewModel.currentIndex, 2)
        viewModel.goNext()
        XCTAssertEqual(viewModel.currentIndex, 2)
        XCTAssertEqual(viewModel.windowTitle, "fake (3 / 3) - 2.png")

        viewModel.goPrevious()
        XCTAssertEqual(viewModel.currentIndex, 1)
    }

    func testDisplaysCurrentPageImage() async {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 5))
        await waitForLoads(viewModel)
        XCTAssertEqual(loadedWidth(viewModel, page: 0), 1)

        viewModel.goNext()
        viewModel.goNext()
        await waitForLoads(viewModel)
        XCTAssertEqual(loadedWidth(viewModel, page: 2), 3)
    }

    func testFailedPageDoesNotStopBook() async {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 3, failingIndex: 1))
        viewModel.goNext()
        await waitForLoads(viewModel)
        guard case .failed = viewModel.state(of: 1) else {
            return XCTFail("失敗したページは failed になる")
        }

        viewModel.goNext()
        await waitForLoads(viewModel)
        XCTAssertEqual(loadedWidth(viewModel, page: 2), 3)
    }

    func testOpeningUnsupportedFileSetsError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yomiview-\(UUID().uuidString).txt")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = makeViewModel()
        viewModel.open(url)
        XCTAssertNotNil(viewModel.openError)
        XCTAssertFalse(viewModel.isBookOpen)
    }

    func testOpeningBrokenFilesShowsErrorAndKeepsCurrentBook() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YomiViewBroken-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let brokenZip = dir.appendingPathComponent("broken.zip")
        let brokenPDF = dir.appendingPathComponent("broken.pdf")
        let emptyFolder = dir.appendingPathComponent("empty", isDirectory: true)
        try Data("not a zip".utf8).write(to: brokenZip)
        try Data("not a pdf".utf8).write(to: brokenPDF)
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)

        let viewModel = makeViewModel()
        viewModel.setProvider(FakeProvider(count: 3))
        for url in [brokenZip, brokenPDF, emptyFolder, dir.appendingPathComponent("missing.cbz")] {
            viewModel.openError = nil
            viewModel.open(url)
            XCTAssertNotNil(viewModel.openError, url.lastPathComponent)
            XCTAssertEqual(viewModel.provider?.title, "fake", "開けなかったときは今の本をそのまま表示する")
        }
    }

    func testOpenDroppedUsesFirstFileURL() throws {
        let viewModel = makeViewModel()
        XCTAssertFalse(viewModel.openDropped([]))
        XCTAssertNotNil(viewModel.openError)

        viewModel.openError = nil
        XCTAssertFalse(viewModel.openDropped([URL(string: "https://example.com/a.zip")!]))
        XCTAssertNotNil(viewModel.openError)

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("YomiViewDrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("1.png"))
        viewModel.openError = nil
        XCTAssertTrue(viewModel.openDropped([folder, folder.appendingPathComponent("1.png")]))
        XCTAssertNil(viewModel.openError)
        XCTAssertEqual(viewModel.provider?.title, folder.lastPathComponent)
    }

    func testReopeningStartsFromFirstPageUnlessRestoreIsOn() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("YomiViewReopen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for i in 1...5 { try Data().write(to: folder.appendingPathComponent("\(i).png")) }

        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        XCTAssertFalse(viewModel.settings.isRestoreLastPage, "既定では読書位置を復元しない")
        viewModel.open(folder)
        viewModel.goNext()
        viewModel.goNext()
        XCTAssertEqual(viewModel.currentIndex, 2)

        viewModel.open(folder)
        XCTAssertEqual(viewModel.currentIndex, 0, "開き直すと最初のページから")
        XCTAssertEqual(viewModel.viewMode, .single, "見開き設定は復元する")

        viewModel.goNext()
        viewModel.goNext()
        viewModel.settings.isRestoreLastPage = true
        viewModel.open(folder)
        XCTAssertEqual(viewModel.currentIndex, 2, "設定をオンにすると最後に読んだページから")
    }

    // MARK: - 見開き

    func testViewModeFollowsContainerShapeUntilToggledManually() {
        let viewModel = makeViewModel()
        viewModel.setProvider(FakeProvider(count: 5))
        viewModel.updateContainerSize(CGSize(width: 800, height: 1000))
        XCTAssertEqual(viewModel.viewMode, .single)
        viewModel.updateContainerSize(CGSize(width: 1400, height: 1000))
        XCTAssertEqual(viewModel.viewMode, .spread)

        viewModel.toggleViewMode()
        XCTAssertEqual(viewModel.viewMode, .single)
        viewModel.updateContainerSize(CGSize(width: 1600, height: 1000))
        XCTAssertEqual(viewModel.viewMode, .single, "手動の指定は自動より優先")
    }

    func testSpreadNavigationMovesByPairs() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .spread
        viewModel.setProvider(FakeProvider(count: 6))
        XCTAssertEqual(viewModel.currentSpread?.pages, [0])

        viewModel.goNext()
        XCTAssertEqual(viewModel.currentSpread?.pages, [1, 2])
        XCTAssertEqual(viewModel.windowTitle, "fake (2 / 6) - 1.png | 2.png")
        viewModel.goNext()
        XCTAssertEqual(viewModel.currentSpread?.pages, [3, 4])
        viewModel.goNext()
        XCTAssertEqual(viewModel.currentSpread?.pages, [5])
        viewModel.goNext()
        XCTAssertEqual(viewModel.currentSpread?.pages, [5])
        viewModel.goPrevious()
        XCTAssertEqual(viewModel.currentSpread?.pages, [3, 4])
    }

    func testRightToLeftSwapsDisplayAndArrowKeys() {
        let viewModel = makeViewModel(direction: .rightToLeft)
        viewModel.manualViewMode = .spread
        viewModel.setProvider(FakeProvider(count: 6))

        viewModel.goLeft()
        XCTAssertEqual(viewModel.currentSpread?.pages, [1, 2])
        XCTAssertEqual(viewModel.displayedPages, [2, 1])
        viewModel.goRight()
        XCTAssertEqual(viewModel.currentSpread?.pages, [0])

        viewModel.toggleReadingDirection()
        viewModel.goRight()
        XCTAssertEqual(viewModel.displayedPages, [1, 2])
    }

    func testWidePageDiscoveredWhileLoadingBecomesSingle() async {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .spread
        viewModel.setProvider(FakeProvider(count: 6, widePages: [2]))
        viewModel.goNext()
        XCTAssertEqual(viewModel.currentSpread?.pages, [1, 2])

        await waitForLoads(viewModel)
        XCTAssertEqual(viewModel.currentSpread?.pages, [1])
        viewModel.goNext()
        XCTAssertEqual(viewModel.currentSpread?.pages, [2])
        viewModel.goNext()
        XCTAssertEqual(viewModel.currentSpread?.pages, [3, 4])
    }

    // MARK: - 先読みとキャッシュ

    func testPrefetchesPagesAroundCurrentSpread() async {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 10))
        viewModel.goNext()
        viewModel.goNext()
        viewModel.goNext()
        XCTAssertEqual(viewModel.pagesToLoad, [3, 4, 5, 2, 1])

        await waitForQueue(viewModel, pages: [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(viewModel.cache.pages).intersection([1, 2, 3, 4, 5]), [1, 2, 3, 4, 5])
    }

    func testPrefetchInSpreadModeIncludesNextSpread() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .spread
        viewModel.setProvider(FakeProvider(count: 10))
        viewModel.goNext()
        XCTAssertEqual(viewModel.pagesToLoad, [1, 2, 3, 4, 0])
    }

    func testCacheIsBoundedWhileReadingThroughBook() async {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 40))
        for _ in 0..<39 {
            viewModel.goNext()
            await waitForLoads(viewModel)
        }
        XCTAssertEqual(viewModel.currentIndex, 39)
        XCTAssertLessThanOrEqual(viewModel.cache.pages.count, ReaderViewModel.cacheCapacity)
    }

    func testRequiredPixelSizeFollowsDisplayedSize() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 3))
        // 仮の大きさ 700x1000 のページを 1000x700 に合わせると高さ 700pt、Retina で 1400px → 1536
        viewModel.updateContainerSize(CGSize(width: 1000, height: 700), displayScale: 2)
        XCTAssertEqual(viewModel.requiredPixelSize, 1536)
        viewModel.updateContainerSize(CGSize(width: 1010, height: 705), displayScale: 2)
        XCTAssertEqual(viewModel.requiredPixelSize, 1536, "少しの変化では読み直さない")
        viewModel.updateContainerSize(CGSize(width: 400, height: 300), displayScale: 1)
        XCTAssertEqual(viewModel.requiredPixelSize, 512)
    }

    private func waitForQueue(_ viewModel: ReaderViewModel, pages: Set<Int>) async {
        for _ in 0..<400 {
            if pages.isSubset(of: Set(viewModel.cache.pages)) { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("先読みが終わらない")
    }

    func testJumpToFirstAndLast() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .spread
        viewModel.setProvider(FakeProvider(count: 6))
        viewModel.goLast()
        XCTAssertEqual(viewModel.currentSpread?.pages, [5])
        viewModel.goFirst()
        XCTAssertEqual(viewModel.currentSpread?.pages, [0])
    }

    func testZoomAndOriginalSizeLoadLargerImages() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 3))
        viewModel.updateContainerSize(CGSize(width: 800, height: 600), displayScale: 2)
        XCTAssertEqual(viewModel.requiredPixelSize, 1280)
        viewModel.zoomIn()
        XCTAssertEqual(viewModel.requiredPixelSize, 1536)
        viewModel.setStretchMode(.none)
        XCTAssertEqual(viewModel.requiredPixelSize, 2048, "オリジナル サイズは 1000pt × 2")
    }

    // MARK: - 表示の操作

    func testZoomSnapsAtOneHundredPercent() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 1))
        viewModel.updateContainerSize(CGSize(width: 700, height: 900), displayScale: 2)
        XCTAssertEqual(viewModel.displayedScale, 0.9, accuracy: 0.001)
        viewModel.zoomIn()
        XCTAssertEqual(viewModel.displayedScale, 1, accuracy: 0.001, "100% をまたぐときは 100% で止まる")
        viewModel.zoomIn()
        XCTAssertEqual(viewModel.displayedScale, 1.2, accuracy: 0.001)
        viewModel.resetScale()
        XCTAssertEqual(viewModel.displayedScale, 0.9, accuracy: 0.001)
    }

    func testRotateNormalizesAngleAndRefitsStretch() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 1))
        viewModel.updateContainerSize(CGSize(width: 1000, height: 1000), displayScale: 1)
        XCTAssertEqual(viewModel.canvas.stretchScale, 1, accuracy: 0.001)
        viewModel.rotateLeft()
        XCTAssertEqual(viewModel.transform.angle, -90)
        XCTAssertEqual(viewModel.canvas.content.width, 1000, accuracy: 0.001, "横倒しでもウィンドウに収まる")
        viewModel.rotateLeft()
        viewModel.rotateLeft()
        XCTAssertEqual(viewModel.transform.angle, 90)
        viewModel.setAngle(190)
        XCTAssertEqual(viewModel.transform.angle, -170)
    }

    func testPageChangeResetsTransform() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 3))
        viewModel.zoomIn()
        viewModel.rotateRight()
        viewModel.toggleFlipHorizontal()
        viewModel.goNext()
        XCTAssertEqual(viewModel.transform, ViewTransform())
    }

    func testScrollMovesWithinImageThenTurnsPage() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 3))
        viewModel.updateContainerSize(CGSize(width: 700, height: 500), displayScale: 1)
        viewModel.setStretchMode(.uniformToHorizontal)
        // 幅に合わせると高さ 1000pt、表示領域 500pt：上端から始まる
        XCTAssertEqual(viewModel.canvas.content.height, 1000, accuracy: 0.001)
        XCTAssertEqual(viewModel.canvas.offset.height, 250, accuracy: 0.001)

        viewModel.scroll(.next)
        XCTAssertEqual(viewModel.currentIndex, 0)
        XCTAssertEqual(viewModel.canvas.offset.height, -150, accuracy: 0.001)
        viewModel.scroll(.next)
        XCTAssertEqual(viewModel.canvas.offset.height, -250, accuracy: 0.001, "下端で止まる")
        viewModel.scroll(.next)
        XCTAssertEqual(viewModel.currentIndex, 1, "下端からさらにスクロールすると次のページ")
        XCTAssertEqual(viewModel.canvas.offset.height, 250, accuracy: 0.001)

        viewModel.scroll(.previous)
        XCTAssertEqual(viewModel.currentIndex, 0, "上端からさらに戻すと前のページ")
        XCTAssertEqual(viewModel.canvas.offset.height, -250, accuracy: 0.001, "前のページは下端から表示")
    }

    func testScrollTurnsPageImmediatelyWhenImageFits() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 3))
        viewModel.updateContainerSize(CGSize(width: 700, height: 1000), displayScale: 1)
        viewModel.scroll(.next)
        XCTAssertEqual(viewModel.currentIndex, 1)
    }

    func testPanIsClampedToContent() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 1))
        viewModel.updateContainerSize(CGSize(width: 700, height: 1000), displayScale: 1)
        viewModel.pan(by: CGSize(width: 300, height: 300))
        XCTAssertEqual(viewModel.canvas.offset, .zero, "収まっている画像は動かない")
        viewModel.setDisplayedScale(2)
        viewModel.pan(by: CGSize(width: 10_000, height: -10_000))
        XCTAssertEqual(viewModel.canvas.offset.width, 350, accuracy: 0.001)
        XCTAssertEqual(viewModel.canvas.offset.height, -500, accuracy: 0.001)
    }

    func testLoupeWheelChangesLoupeScale() {
        let viewModel = makeViewModel()
        viewModel.setProvider(FakeProvider(count: 3))
        viewModel.isLoupeActive = true
        viewModel.scroll(.previous)
        XCTAssertEqual(viewModel.loupeScale, 3)
        viewModel.scroll(.next)
        viewModel.scroll(.next)
        viewModel.scroll(.next)
        XCTAssertEqual(viewModel.loupeScale, 1)
        XCTAssertEqual(viewModel.currentIndex, 0, "ルーペ中のホイールではページを送らない")
    }

    func testCurrentPageIsKeptWhenSwitchingModes() {
        let viewModel = makeViewModel()
        viewModel.manualViewMode = .single
        viewModel.setProvider(FakeProvider(count: 6))
        viewModel.goNext()
        viewModel.goNext()
        viewModel.toggleViewMode()
        XCTAssertEqual(viewModel.currentSpread?.pages, [1, 2])
    }
}
