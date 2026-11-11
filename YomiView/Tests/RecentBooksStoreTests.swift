import XCTest
@testable import YomiView

@MainActor
final class RecentBooksStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "YomiViewRecentTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/yomiview-books/\(name)")
    }

    func testRecordOpenMovesBookToFront() {
        let store = RecentBooksStore(defaults: defaults)
        store.recordOpen(url("a.zip"))
        store.recordOpen(url("b.zip"))
        store.recordOpen(url("a.zip"))
        XCTAssertEqual(store.entries.map(\.displayName), ["a.zip", "b.zip"])
    }

    func testKeepsAtMostTwentyBooks() {
        let store = RecentBooksStore(defaults: defaults)
        for i in 0..<25 { store.recordOpen(url("\(i).zip")) }
        XCTAssertEqual(store.entries.count, 20)
        XCTAssertEqual(store.entries.first?.displayName, "24.zip")
        XCTAssertEqual(store.entries.last?.displayName, "5.zip")
    }

    func testPositionIsPersistedAcrossInstances() {
        let store = RecentBooksStore(defaults: defaults)
        store.recordOpen(url("a.zip"))
        store.updatePosition(of: url("a.zip"), page: 12, viewMode: .spread)

        let reloaded = RecentBooksStore(defaults: defaults)
        let entry = reloaded.entry(for: url("a.zip"))
        XCTAssertEqual(entry?.lastPage, 12)
        XCTAssertEqual(entry?.viewMode, .spread)
    }

    func testReopeningKeepsSavedPosition() {
        let store = RecentBooksStore(defaults: defaults)
        store.recordOpen(url("a.zip"))
        store.updatePosition(of: url("a.zip"), page: 7, viewMode: nil)
        store.recordOpen(url("b.zip"))
        let entry = store.recordOpen(url("a.zip"))
        XCTAssertEqual(entry.lastPage, 7)
        XCTAssertNil(entry.viewMode)
    }

    func testEquivalentPathsAreTheSameBook() {
        let store = RecentBooksStore(defaults: defaults)
        store.recordOpen(URL(fileURLWithPath: "/tmp/yomiview-books/x/../a.zip"))
        store.recordOpen(url("a.zip"))
        XCTAssertEqual(store.entries.count, 1)
    }

    func testUpdateForUnknownBookDoesNothing() {
        let store = RecentBooksStore(defaults: defaults)
        store.updatePosition(of: url("a.zip"), page: 3, viewMode: nil)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testClear() {
        let store = RecentBooksStore(defaults: defaults)
        store.recordOpen(url("a.zip"))
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(RecentBooksStore(defaults: defaults).entries.isEmpty)
    }
}
