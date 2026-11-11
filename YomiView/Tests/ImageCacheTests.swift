import CoreGraphics
import XCTest
@testable import YomiView

final class ImageCacheTests: XCTestCase {
    private func image(width: Int = 100, height: Int = 100) -> PageImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return PageImage(cgImage: context.makeImage()!)
    }

    func testEvictsLeastRecentlyUsedWhenOverCapacity() {
        let cache = ImageCache(capacity: 3)
        for page in 0..<3 { cache.insert(image(), for: page, maxPixelSize: 100) }
        XCTAssertEqual(cache.pages, [0, 1, 2])

        cache.insert(image(), for: 3, maxPixelSize: 100)
        XCTAssertEqual(cache.pages, [1, 2, 3])
        XCTAssertNil(cache.image(for: 0))
    }

    func testAccessMakesEntryRecentlyUsed() {
        let cache = ImageCache(capacity: 3)
        for page in 0..<3 { cache.insert(image(), for: page, maxPixelSize: 100) }
        XCTAssertNotNil(cache.image(for: 0))

        cache.insert(image(), for: 3, maxPixelSize: 100)
        XCTAssertEqual(cache.pages, [2, 0, 3])
        XCTAssertNotNil(cache.image(for: 0))
        XCTAssertNil(cache.image(for: 1))
    }

    func testReinsertReplacesWithoutGrowing() {
        let cache = ImageCache(capacity: 2)
        cache.insert(image(), for: 0, maxPixelSize: 100)
        cache.insert(image(width: 200, height: 200), for: 0, maxPixelSize: 200)
        XCTAssertEqual(cache.pages, [0])
        XCTAssertEqual(cache.image(for: 0)?.cgImage.width, 200)
    }

    func testSmallerImageIsNotSufficientForLargerDisplay() {
        let cache = ImageCache(capacity: 2)
        // 2000px の元画像を 1000px で読み込んだ
        cache.insert(image(width: 1000, height: 500), for: 0, maxPixelSize: 1000)
        XCTAssertTrue(cache.contains(0, sufficientFor: 1000))
        XCTAssertTrue(cache.contains(0, sufficientFor: 512))
        XCTAssertFalse(cache.contains(0, sufficientFor: 2048))
    }

    func testImageAtNaturalSizeIsAlwaysSufficient() {
        let cache = ImageCache(capacity: 2)
        // 元画像が 300px しかなく、1000px を要求しても 300px だった
        cache.insert(image(width: 300, height: 200), for: 0, maxPixelSize: 1000)
        XCTAssertTrue(cache.contains(0, sufficientFor: 4096))
    }

    func testRemoveAll() {
        let cache = ImageCache(capacity: 2)
        cache.insert(image(), for: 0, maxPixelSize: 100)
        cache.removeAll()
        XCTAssertEqual(cache.pages, [])
        XCTAssertFalse(cache.contains(0, sufficientFor: 1))
    }
}
