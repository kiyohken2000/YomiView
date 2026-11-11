import CoreGraphics
import XCTest
@testable import YomiView

final class PDFPageProviderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YomiViewPDFTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// 指定サイズのページを持つ PDF を作る。
    private func makePDF(named name: String, pageSizes: [CGSize]) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        var mediaBox = CGRect(origin: .zero, size: pageSizes.first ?? .zero)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        for size in pageSizes {
            var box = CGRect(origin: .zero, size: size)
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)]
            context.beginPDFPage(info as CFDictionary)
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2))
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    func testOpensAllPages() throws {
        let sizes = Array(repeating: CGSize(width: 500, height: 700), count: 15)
        let provider = try PDFPageProvider(pdfURL: try makePDF(named: "manga.pdf", pageSizes: sizes))

        XCTAssertEqual(provider.title, "manga")
        XCTAssertEqual(provider.pageCount, 15)
        XCTAssertEqual(provider.pages.map(\.kind), (0..<15).map { .pdfPage($0) })
    }

    func testRendersAtRequestedSize() throws {
        let provider = try PDFPageProvider(pdfURL: try makePDF(
            named: "a.pdf", pageSizes: [CGSize(width: 500, height: 1000)]
        ))

        let page = try provider.loadImage(at: 0, maxPixelSize: 400)

        XCTAssertEqual(page.cgImage.height, 400)
        XCTAssertEqual(page.cgImage.width, 200)
        XCTAssertEqual(page.pointSize, CGSize(width: 500, height: 1000))
        XCTAssertFalse(page.isWide)
    }

    func testRenderScaleIsCapped() throws {
        let provider = try PDFPageProvider(pdfURL: try makePDF(
            named: "small.pdf", pageSizes: [CGSize(width: 100, height: 200)]
        ))

        let page = try provider.loadImage(at: 0, maxPixelSize: 10_000)

        XCTAssertEqual(page.cgImage.height, 200 * Int(PDFPageProvider.maxRenderScale))
    }

    func testWidePage() throws {
        let provider = try PDFPageProvider(pdfURL: try makePDF(
            named: "wide.pdf", pageSizes: [CGSize(width: 1000, height: 700)]
        ))
        XCTAssertTrue(try provider.loadImage(at: 0, maxPixelSize: 100).isWide)
    }

    func testBrokenPDFThrows() throws {
        let url = tempDir.appendingPathComponent("broken.pdf")
        try Data("%PDF-1.4 broken".utf8).write(to: url)
        XCTAssertThrowsError(try PDFPageProvider(pdfURL: url)) { error in
            XCTAssertEqual(error as? BookError, .unreadablePDF("broken.pdf"))
        }
    }

    func testOutOfRangePageThrows() throws {
        let provider = try PDFPageProvider(pdfURL: try makePDF(
            named: "a.pdf", pageSizes: [CGSize(width: 100, height: 100)]
        ))
        XCTAssertThrowsError(try provider.loadImage(at: 1, maxPixelSize: 100)) { error in
            XCTAssertEqual(error as? BookError, .pageOutOfRange(1))
        }
    }

    func testBookSourceDetectsPDF() throws {
        let url = try makePDF(named: "B.PDF", pageSizes: [CGSize(width: 100, height: 100)])
        XCTAssertEqual(try BookSource.detect(url), .pdf(url))
        XCTAssertTrue(try BookSource.detect(url).makeProvider() is PDFPageProvider)
    }
}
