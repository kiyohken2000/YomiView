import CoreGraphics
import XCTest
@testable import YomiView

@MainActor
final class ThumbnailStoreTests: XCTestCase {
    nonisolated private static func image(width: Int) -> CGImage {
        CGContext(
            data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!.makeImage()!
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("時間内に終わらない")
    }

    func testLoadsRequestedThumbnails() async {
        let store = ThumbnailStore<Int>(capacity: 10) { Self.image(width: $0 + 1) }
        store.request(3)
        await waitUntil { store.image(for: 3) != nil }
        XCTAssertEqual(store.image(for: 3)?.width, 4)
        XCTAssertNil(store.image(for: 2))
    }

    func testCapacityIsBounded() async {
        let store = ThumbnailStore<Int>(capacity: 3) { Self.image(width: $0 + 1) }
        for i in 0..<10 { store.request(i) }
        // 後から要求したものを先に作るため、最初に要求した 0 が最後に作られる
        await waitUntil { store.image(for: 0) != nil }
        XCTAssertEqual(store.count, 3)
        XCTAssertNotNil(store.image(for: 1))
        XCTAssertNil(store.image(for: 9), "古いものから捨てる")
    }

    func testFailureIsRemembered() async {
        let store = ThumbnailStore<Int>(capacity: 3) { _ in throw BookError.pageOutOfRange(0) }
        store.request(1)
        await waitUntil { store.hasFailed(1) }
        XCTAssertNil(store.image(for: 1))
    }

    func testResetDiscardsOldResults() async {
        let store = ThumbnailStore<Int>(capacity: 3) { _ in Self.image(width: 1) }
        store.request(0)
        await waitUntil { store.image(for: 0) != nil }
        store.reset { _ in Self.image(width: 9) }
        XCTAssertNil(store.image(for: 0))
        store.request(0)
        await waitUntil { store.image(for: 0) != nil }
        XCTAssertEqual(store.image(for: 0)?.width, 9)
    }

    func testCancelledRequestIsNotLoaded() async {
        let gate = DispatchSemaphore(value: 0)
        let store = ThumbnailStore<Int>(capacity: 10) { key in
            if key == 0 { gate.wait() }
            return Self.image(width: key + 1)
        }
        store.request(0)   // 読み込み中で止める
        try? await Task.sleep(nanoseconds: 20_000_000)
        store.request(1)
        store.cancel(1)
        gate.signal()
        await waitUntil { store.image(for: 0) != nil }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(store.image(for: 1))
    }

    func testPageThumbnailsFollowOpenedBook() async {
        let suite = "YomiViewThumbTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let viewModel = ReaderViewModel(
            settings: AppSettings(defaults: defaults), recentBooks: RecentBooksStore(defaults: defaults)
        )
        viewModel.setProvider(FakeProvider(count: 5))
        viewModel.pageThumbnails.request(4)
        await waitUntil { viewModel.pageThumbnails.image(for: 4) != nil }
        XCTAssertEqual(viewModel.pageThumbnails.image(for: 4)?.width, 5)

        viewModel.setProvider(FakeProvider(count: 2))
        XCTAssertNil(viewModel.pageThumbnails.image(for: 4), "別の本を開いたら捨てる")
    }
}
