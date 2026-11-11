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
        return ReaderViewModel(settings: settings)
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
