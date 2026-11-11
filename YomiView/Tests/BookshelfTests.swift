import XCTest
@testable import YomiView

@MainActor
final class BookshelfTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YomiViewShelf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "YomiViewShelfTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// 1ページの PNG を持つフォルダの本を作る
    private func makeFolderBook(_ name: String, in parent: URL? = nil) throws -> URL {
        let folder = (parent ?? root).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("1.png"))
        return folder
    }

    private func touch(_ name: String, bytes: Int = 0, date: Date? = nil) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 0, count: bytes).write(to: url)
        if let date {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        return url
    }

    // MARK: - 一覧

    func testListsFoldersFirstThenBookFilesInNaturalOrder() throws {
        _ = try makeFolderBook("vol10")
        _ = try makeFolderBook("vol2")
        _ = try touch("b10.zip")
        _ = try touch("b2.cbz")
        _ = try touch("a.pdf")
        _ = try touch("note.txt")
        _ = try touch("cover.jpg")
        _ = try touch(".hidden.zip")

        let items = try BookshelfListing.items(in: root, order: .fileName)
        XCTAssertEqual(items.map(\.name), ["vol2", "vol10", "a.pdf", "b2.cbz", "b10.zip"])
        XCTAssertEqual(items.map(\.kind), [.folder, .folder, .pdf, .archive, .archive])
    }

    func testSortOrders() throws {
        let now = Date()
        _ = try touch("a.zip", bytes: 30, date: now.addingTimeInterval(-100))
        _ = try touch("b.pdf", bytes: 10, date: now.addingTimeInterval(-300))
        _ = try touch("c.cbz", bytes: 20, date: now.addingTimeInterval(-200))

        func names(_ order: FolderOrder) throws -> [String] {
            try BookshelfListing.items(in: root, order: order).map(\.name)
        }
        XCTAssertEqual(try names(.fileNameDescending), ["c.cbz", "b.pdf", "a.zip"])
        XCTAssertEqual(try names(.fileType), ["c.cbz", "b.pdf", "a.zip"])
        XCTAssertEqual(try names(.fileTypeDescending), ["a.zip", "b.pdf", "c.cbz"])
        XCTAssertEqual(try names(.timeStamp), ["b.pdf", "c.cbz", "a.zip"])
        XCTAssertEqual(try names(.timeStampDescending), ["a.zip", "c.cbz", "b.pdf"])
        XCTAssertEqual(try names(.size), ["b.pdf", "c.cbz", "a.zip"])
        XCTAssertEqual(try names(.sizeDescending), ["a.zip", "c.cbz", "b.pdf"])
        XCTAssertEqual(Set(try names(.random)), ["a.zip", "b.pdf", "c.cbz"])
    }

    func testRandomOrderIsStableForSameSeed() throws {
        for i in 0..<10 { _ = try touch("\(i).zip") }
        let a = try BookshelfListing.items(in: root, order: .random, randomSeed: 42)
        let b = try BookshelfListing.items(in: root, order: .random, randomSeed: 42)
        XCTAssertEqual(a, b)
    }

    func testNeighbor() throws {
        let items = try [touch("1.zip"), touch("2.zip"), touch("3.zip")].map {
            BookshelfItem(url: $0, kind: .archive, modified: .distantPast, size: 0)
        }
        XCTAssertEqual(BookshelfListing.neighbor(of: items[1].url, offset: 1, in: items), items[2])
        XCTAssertEqual(BookshelfListing.neighbor(of: items[1].url, offset: -1, in: items), items[0])
        XCTAssertNil(BookshelfListing.neighbor(of: items[2].url, offset: 1, in: items))
        XCTAssertNil(BookshelfListing.neighbor(of: root.appendingPathComponent("x.zip"), offset: 1, in: items))
    }

    // MARK: - 本棚の移動

    func testPlaceNavigation() throws {
        let sub = try makeFolderBook("sub")
        let model = BookshelfModel(defaults: defaults)
        model.move(to: root)
        model.move(to: sub)
        XCTAssertTrue(model.canGoBack)
        model.goBack()
        XCTAssertEqual(model.place, root.standardizedFileURL)
        XCTAssertEqual(model.selected, sub.standardizedFileURL, "戻ったときは元いたフォルダを選択する")
        model.goForward()
        XCTAssertEqual(model.place, sub.standardizedFileURL)
        model.goUp()
        XCTAssertEqual(model.place, root.standardizedFileURL)
        XCTAssertEqual(model.selected, sub.standardizedFileURL)
    }

    func testFilter() throws {
        _ = try touch("apple.zip")
        _ = try touch("banana.zip")
        let model = BookshelfModel(defaults: defaults)
        model.move(to: root)
        model.filterText = "APP"
        XCTAssertEqual(model.visibleItems.map(\.name), ["apple.zip"])
    }

    func testOrderIsSaved() {
        let model = BookshelfModel(defaults: defaults)
        model.order = .sizeDescending
        XCTAssertEqual(BookshelfModel(defaults: defaults).order, .sizeDescending)
    }

    // MARK: - 前後の本と本の履歴

    private func makeViewModel() -> ReaderViewModel {
        ReaderViewModel(
            settings: AppSettings(defaults: defaults),
            recentBooks: RecentBooksStore(defaults: defaults),
            bookshelf: BookshelfModel(defaults: defaults)
        )
    }

    func testOpeningBookRevealsItInBookshelf() throws {
        let book = try makeFolderBook("b1")
        let viewModel = makeViewModel()
        viewModel.open(book)
        XCTAssertEqual(viewModel.bookshelf.place, root.standardizedFileURL)
        XCTAssertEqual(viewModel.bookshelf.selected, book.standardizedFileURL)
    }

    func testNextAndPreviousBook() throws {
        let b1 = try makeFolderBook("b1")
        _ = try makeFolderBook("b2")
        let b3 = try makeFolderBook("b3")
        let viewModel = makeViewModel()
        viewModel.open(b1)

        viewModel.openNextBook()
        XCTAssertEqual(viewModel.provider?.title, "b2")
        viewModel.openNextBook()
        XCTAssertEqual(viewModel.bookURL?.standardizedFileURL, b3.standardizedFileURL)
        viewModel.openNextBook()
        XCTAssertEqual(viewModel.provider?.title, "b3")
        XCTAssertEqual(viewModel.infoMessage?.text, "次のブックはありません")

        viewModel.openPreviousBook()
        XCTAssertEqual(viewModel.provider?.title, "b2")
    }

    func testNextBookSkipsOverUnopenableItemWithNotice() throws {
        let b1 = try makeFolderBook("b1")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("b2-empty"), withIntermediateDirectories: true)
        _ = try makeFolderBook("b3")
        let viewModel = makeViewModel()
        viewModel.open(b1)

        viewModel.openNextBook()
        XCTAssertNil(viewModel.openError, "前後の本の移動ではアラートを出さない")
        XCTAssertNotNil(viewModel.infoMessage)
        XCTAssertEqual(viewModel.provider?.title, "b1")
        viewModel.openNextBook()
        XCTAssertEqual(viewModel.provider?.title, "b3")
    }

    func testBookHistoryBackAndForward() throws {
        let b1 = try makeFolderBook("b1")
        let b2 = try makeFolderBook("b2")
        let b3 = try makeFolderBook("b3")
        let viewModel = makeViewModel()
        viewModel.open(b1)
        viewModel.open(b2)
        viewModel.open(b3)
        XCTAssertFalse(viewModel.canGoForwardBook)

        viewModel.goBackBook()
        XCTAssertEqual(viewModel.provider?.title, "b2")
        viewModel.goBackBook()
        XCTAssertEqual(viewModel.provider?.title, "b1")
        XCTAssertFalse(viewModel.canGoBackBook)
        viewModel.goForwardBook()
        XCTAssertEqual(viewModel.provider?.title, "b2")

        // 途中で別の本を開くと、進む履歴は消える
        viewModel.open(b1)
        XCTAssertFalse(viewModel.canGoForwardBook)
    }

    func testParentBook() throws {
        let parent = try makeFolderBook("parent")
        let child = try makeFolderBook("child", in: parent)
        let viewModel = makeViewModel()
        viewModel.open(child)
        viewModel.openParentBook()
        XCTAssertEqual(viewModel.provider?.title, "parent")
    }
}
