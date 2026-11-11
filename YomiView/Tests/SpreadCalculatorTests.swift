import XCTest
@testable import YomiView

final class SpreadCalculatorTests: XCTestCase {
    private func pages(_ spreads: [Spread]) -> [[Int]] {
        spreads.map(\.pages)
    }

    // MARK: - ページ数ごとの組み合わせ

    func testEmptyBook() {
        XCTAssertEqual(SpreadCalculator.spreads(pageCount: 0, mode: .spread), [])
        XCTAssertEqual(SpreadCalculator.spreads(pageCount: 0, mode: .single), [])
    }

    func testSinglePageModeShowsEveryPageAlone() {
        XCTAssertEqual(pages(SpreadCalculator.spreads(pageCount: 3, mode: .single)), [[0], [1], [2]])
    }

    func testOnePageBook() {
        XCTAssertEqual(pages(SpreadCalculator.spreads(pageCount: 1, mode: .spread)), [[0]])
    }

    func testCoverIsSingleByDefault() {
        // 表紙単独、残りは2ページずつ
        XCTAssertEqual(pages(SpreadCalculator.spreads(pageCount: 5, mode: .spread)), [[0], [1, 2], [3, 4]])
    }

    func testLeftoverLastPageIsSingle() {
        // 表紙単独のあと残りが奇数なら、最後のページは単独
        XCTAssertEqual(pages(SpreadCalculator.spreads(pageCount: 4, mode: .spread)), [[0], [1, 2], [3]])
        XCTAssertEqual(pages(SpreadCalculator.spreads(pageCount: 2, mode: .spread)), [[0], [1]])
    }

    func testWithoutCoverSingleOddPageCount() {
        let options = SpreadCalculator.Options(coverSingle: false, landscapeSingle: true)
        XCTAssertEqual(
            pages(SpreadCalculator.spreads(pageCount: 5, mode: .spread, options: options)),
            [[0, 1], [2, 3], [4]]
        )
        XCTAssertEqual(
            pages(SpreadCalculator.spreads(pageCount: 4, mode: .spread, options: options)),
            [[0, 1], [2, 3]]
        )
    }

    // MARK: - 横長ページ

    func testWidePageIsSingleAndShiftsPairs() {
        let spreads = SpreadCalculator.spreads(pageCount: 7, mode: .spread, isWide: { $0 == 2 })
        XCTAssertEqual(pages(spreads), [[0], [1], [2], [3, 4], [5, 6]])
    }

    func testWidePageAtStartOfPair() {
        let spreads = SpreadCalculator.spreads(pageCount: 6, mode: .spread, isWide: { $0 == 3 })
        XCTAssertEqual(pages(spreads), [[0], [1, 2], [3], [4, 5]])
    }

    func testWidePagesCanBePairedWhenOptionIsOff() {
        let options = SpreadCalculator.Options(coverSingle: true, landscapeSingle: false)
        let spreads = SpreadCalculator.spreads(pageCount: 5, mode: .spread, options: options, isWide: { _ in true })
        XCTAssertEqual(pages(spreads), [[0], [1, 2], [3, 4]])
    }

    func testEveryPageIsCoveredExactlyOnceInOrder() {
        for count in 0...12 {
            for cover in [true, false] {
                let options = SpreadCalculator.Options(coverSingle: cover, landscapeSingle: true)
                let spreads = SpreadCalculator.spreads(
                    pageCount: count, mode: .spread, options: options, isWide: { $0 % 5 == 3 }
                )
                XCTAssertEqual(spreads.flatMap(\.pages), Array(0..<count), "count=\(count) cover=\(cover)")
                XCTAssertTrue(spreads.allSatisfy { (1...2).contains($0.pages.count) })
            }
        }
    }

    // MARK: - 右開き

    func testRightToLeftSwapsPagesInSpread() {
        let spread = Spread(pages: [1, 2])
        XCTAssertEqual(SpreadCalculator.displayOrder(of: spread, direction: .rightToLeft), [2, 1])
        XCTAssertEqual(SpreadCalculator.displayOrder(of: spread, direction: .leftToRight), [1, 2])
    }

    func testSinglePageDisplayOrderIsUnaffectedByDirection() {
        let spread = Spread(pages: [0])
        XCTAssertEqual(SpreadCalculator.displayOrder(of: spread, direction: .rightToLeft), [0])
    }

    func testSpreadIndexContainingPage() {
        let spreads = SpreadCalculator.spreads(pageCount: 5, mode: .spread)
        XCTAssertEqual(SpreadCalculator.spreadIndex(containing: 0, in: spreads), 0)
        XCTAssertEqual(SpreadCalculator.spreadIndex(containing: 2, in: spreads), 1)
        XCTAssertEqual(SpreadCalculator.spreadIndex(containing: 4, in: spreads), 2)
        XCTAssertNil(SpreadCalculator.spreadIndex(containing: 5, in: spreads))
    }
}
