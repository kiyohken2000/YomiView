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
        XCTAssertEqual(viewModel.windowTitle, "fake (1 / 3)")

        viewModel.goPrevious()
        XCTAssertEqual(viewModel.currentIndex, 0)

        viewModel.goNext()
        viewModel.goNext()
        XCTAssertEqual(viewModel.currentIndex, 2)
        viewModel.goNext()
        XCTAssertEqual(viewModel.currentIndex, 2)
        XCTAssertEqual(viewModel.windowTitle, "fake (3 / 3)")

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
        XCTAssertEqual(viewModel.windowTitle, "fake (2-3 / 6)")
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

    func testRequiredPixelSizeFollowsContainer() {
        let viewModel = makeViewModel()
        viewModel.updateContainerSize(CGSize(width: 1000, height: 700), displayScale: 2)
        XCTAssertEqual(viewModel.requiredPixelSize, 2048)
        viewModel.updateContainerSize(CGSize(width: 1010, height: 700), displayScale: 2)
        XCTAssertEqual(viewModel.requiredPixelSize, 2048, "少しの変化では読み直さない")
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

    func testOriginalZoomLoadsLargerImages() {
        let viewModel = makeViewModel()
        viewModel.updateContainerSize(CGSize(width: 800, height: 600), displayScale: 2)
        XCTAssertEqual(viewModel.requiredPixelSize, 1792)
        viewModel.zoomMode = .original
        XCTAssertEqual(viewModel.requiredPixelSize, ReaderViewModel.originalMaxPixelSize)
    }

    // MARK: - 読書位置の復元

    func testReopeningBookRestoresPageAndViewMode() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("YomiViewRestore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for i in 1...8 {
            try Data().write(to: folder.appendingPathComponent("\(i).png"))
        }

        let first = makeViewModel()
        first.open(folder)
        XCTAssertNil(first.openError)
        first.manualViewMode = .single
        first.goNext()
        first.goNext()
        first.goNext()
        first.toggleViewMode()
        XCTAssertEqual(first.currentIndex, 3)

        // 別のウィンドウ（再起動後を想定）で同じ本を開く
        let second = makeViewModel()
        second.open(folder)
        XCTAssertEqual(second.currentIndex, 3)
        XCTAssertEqual(second.manualViewMode, .spread)
        XCTAssertEqual(second.currentSpread?.pages, [3, 4])
    }

    func testRestoredPageIsClampedToBook() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("YomiViewClamp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("1.png"))

        let store = RecentBooksStore(defaults: defaults)
        store.recordOpen(folder)
        store.updatePosition(of: folder, page: 50, viewMode: nil)

        let viewModel = makeViewModel()
        viewModel.open(folder)
        XCTAssertEqual(viewModel.currentIndex, 0)
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
