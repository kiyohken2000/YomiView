import CoreGraphics
import XCTest
@testable import YomiView

/// 読み込んだページ番号を幅に入れた画像を返すテスト用 Provider。
private final class FakeProvider: PageProvider, @unchecked Sendable {
    let title = "fake"
    let pages: [PageItem]
    let failingIndex: Int?

    init(count: Int, failingIndex: Int? = nil) {
        pages = (0..<count).map { PageItem(index: $0, name: "\($0).png", kind: .archiveEntry(path: "\($0).png")) }
        self.failingIndex = failingIndex
    }

    func loadImage(at index: Int, maxPixelSize: Int) throws -> PageImage {
        if index == failingIndex { throw BookError.imageDecodeFailed(pages[index].name) }
        let context = CGContext(
            data: nil, width: index + 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return PageImage(cgImage: context.makeImage()!)
    }
}

@MainActor
final class ReaderViewModelTests: XCTestCase {
    private func waitForLoad(_ viewModel: ReaderViewModel) async {
        for _ in 0..<200 {
            if viewModel.pageState != .loading { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("ページの読み込みが終わらない")
    }

    private func loadedWidth(_ viewModel: ReaderViewModel) -> Int? {
        if case .loaded(let image) = viewModel.pageState { return image.cgImage.width }
        return nil
    }

    func testNavigationStaysWithinBook() async {
        let viewModel = ReaderViewModel()
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
        let viewModel = ReaderViewModel()
        viewModel.setProvider(FakeProvider(count: 5))
        await waitForLoad(viewModel)
        XCTAssertEqual(loadedWidth(viewModel), 1)

        viewModel.goNext()
        viewModel.goNext()
        await waitForLoad(viewModel)
        XCTAssertEqual(loadedWidth(viewModel), 3)
    }

    func testFailedPageDoesNotStopBook() async {
        let viewModel = ReaderViewModel()
        viewModel.setProvider(FakeProvider(count: 3, failingIndex: 1))
        viewModel.goNext()
        await waitForLoad(viewModel)
        guard case .failed = viewModel.pageState else {
            return XCTFail("失敗したページは failed になる")
        }

        viewModel.goNext()
        await waitForLoad(viewModel)
        XCTAssertEqual(loadedWidth(viewModel), 3)
    }

    func testOpeningUnsupportedFileSetsError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yomiview-\(UUID().uuidString).txt")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = ReaderViewModel()
        viewModel.open(url)
        XCTAssertNotNil(viewModel.openError)
        XCTAssertFalse(viewModel.isBookOpen)
    }
}
