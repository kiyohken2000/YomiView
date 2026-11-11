import XCTest
@testable import YomiView

final class NaturalSortTests: XCTestCase {
    func testNumbersAreComparedByValue() {
        let input = ["page10.jpg", "page2.jpg", "page1.jpg", "page100.jpg", "page20.jpg"]
        XCTAssertEqual(
            NaturalSort.sorted(input),
            ["page1.jpg", "page2.jpg", "page10.jpg", "page20.jpg", "page100.jpg"]
        )
    }

    func testLeadingZerosAndPlainNumbers() {
        let input = ["010.png", "9.png", "001.png", "2.png"]
        XCTAssertEqual(NaturalSort.sorted(input), ["001.png", "2.png", "9.png", "010.png"])
    }

    func testMultipleNumberGroups() {
        let input = ["v2_p10.jpg", "v10_p1.jpg", "v2_p9.jpg", "v1_p20.jpg"]
        XCTAssertEqual(NaturalSort.sorted(input), ["v1_p20.jpg", "v2_p9.jpg", "v2_p10.jpg", "v10_p1.jpg"])
    }

    func testCaseInsensitiveOrdering() {
        let input = ["b.jpg", "A.jpg", "c.jpg"]
        XCTAssertEqual(NaturalSort.sorted(input), ["A.jpg", "b.jpg", "c.jpg"])
    }

    func testJapaneseNamesWithNumbers() {
        let input = ["第10話.jpg", "第2話.jpg", "第1話.jpg"]
        XCTAssertEqual(NaturalSort.sorted(input), ["第1話.jpg", "第2話.jpg", "第10話.jpg"])
    }

    func testPathsInArchiveAreSortedByFolderThenFile() {
        let input = ["vol10/1.jpg", "vol2/10.jpg", "vol2/2.jpg", "vol1/1.jpg"]
        XCTAssertEqual(NaturalSort.sorted(input), ["vol1/1.jpg", "vol2/2.jpg", "vol2/10.jpg", "vol10/1.jpg"])
    }

    func testOrderIsDeterministicForNamesThatCompareEqual() {
        let a = NaturalSort.sorted(["a.jpg", "A.jpg"])
        let b = NaturalSort.sorted(["A.jpg", "a.jpg"])
        XCTAssertEqual(a, b)
    }
}
