import Foundation
import Observation

/// 本棚の並び順（NeeView/SidePanels/Bookshelf/FolderList/FolderOrder.cs から移植。登録順・パス順は単一フォルダの一覧では使わないため除外）。
enum FolderOrder: String, CaseIterable, Identifiable, Codable {
    case fileName
    case fileNameDescending
    case fileType
    case fileTypeDescending
    case timeStamp
    case timeStampDescending
    case size
    case sizeDescending
    case random

    var id: String { rawValue }

    /// NeeView の表示名（Languages/ja.restext の SortOrder.*）
    var label: String {
        switch self {
        case .fileName: return "名前↑"
        case .fileNameDescending: return "名前↓"
        case .fileType: return "種類↑"
        case .fileTypeDescending: return "種類↓"
        case .timeStamp: return "日付↑"
        case .timeStampDescending: return "日付↓"
        case .size: return "サイズ↑"
        case .sizeDescending: return "サイズ↓"
        case .random: return "シャッフル"
        }
    }
}

/// 本棚の1項目（フォルダ、または本として開けるファイル）。
struct BookshelfItem: Identifiable, Equatable, Hashable {
    enum Kind: Equatable, Hashable {
        case folder
        case archive
        case pdf
    }

    let url: URL
    let kind: Kind
    let modified: Date
    /// ファイルのサイズ（フォルダは -1）
    let size: Int64

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isFolder: Bool { kind == .folder }
}

/// 本棚の一覧の作成と並び替え。副作用のない関数だけを持つ。
enum BookshelfListing {
    /// フォルダの直下から、本棚に表示する項目（フォルダ、ZIP / CBZ、PDF）を集めて並べる。隠しファイルは除外する。
    static func items(in folder: URL, order: FolderOrder, randomSeed: UInt64 = 0) throws -> [BookshelfItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )
        let items: [BookshelfItem] = contents.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let modified = values.contentModificationDate ?? .distantPast
            if values.isDirectory == true, values.isPackage != true {
                return BookshelfItem(url: url, kind: .folder, modified: modified, size: -1)
            }
            let ext = url.pathExtension.lowercased()
            let size = Int64(values.fileSize ?? 0)
            if BookSource.archiveExtensions.contains(ext) {
                return BookshelfItem(url: url, kind: .archive, modified: modified, size: size)
            }
            if ext == "pdf" {
                return BookshelfItem(url: url, kind: .pdf, modified: modified, size: size)
            }
            return nil
        }
        return sorted(items, order: order, randomSeed: randomSeed)
    }

    /// NeeView の既定（フォルダを先に並べる）に従い、フォルダとファイルをそれぞれ並べる。
    static func sorted(_ items: [BookshelfItem], order: FolderOrder, randomSeed: UInt64 = 0) -> [BookshelfItem] {
        let folders = items.filter(\.isFolder)
        let files = items.filter { !$0.isFolder }
        return sortGroup(folders, order: order, seed: randomSeed) + sortGroup(files, order: order, seed: randomSeed)
    }

    private static func sortGroup(_ items: [BookshelfItem], order: FolderOrder, seed: UInt64) -> [BookshelfItem] {
        func byName(_ a: BookshelfItem, _ b: BookshelfItem) -> Bool {
            NaturalSort.areInIncreasingOrder(a.name, b.name)
        }
        switch order {
        case .fileName:
            return items.sorted(by: byName)
        case .fileNameDescending:
            return items.sorted { byName($1, $0) }
        case .fileType, .fileTypeDescending:
            // 拡張子で並べ、同じ拡張子の中は名前順（NeeView の ComparerFileType）
            let ascending = items.sorted { a, b in
                let extA = a.url.pathExtension.lowercased(), extB = b.url.pathExtension.lowercased()
                return extA == extB ? byName(a, b) : NaturalSort.areInIncreasingOrder(extA, extB)
            }
            return order == .fileType ? ascending : ascending.reversed()
        case .timeStamp:
            return items.sorted { $0.modified == $1.modified ? byName($0, $1) : $0.modified < $1.modified }
        case .timeStampDescending:
            return items.sorted { $0.modified == $1.modified ? byName($0, $1) : $0.modified > $1.modified }
        case .size:
            return items.sorted { $0.size == $1.size ? byName($0, $1) : $0.size < $1.size }
        case .sizeDescending:
            return items.sorted { $0.size == $1.size ? byName($0, $1) : $0.size > $1.size }
        case .random:
            var generator = SeededGenerator(seed: seed)
            return items.sorted(by: byName).shuffled(using: &generator)
        }
    }

    /// 一覧の中で `url` の前後の項目。見つからなければ nil。
    static func neighbor(of url: URL, offset: Int, in items: [BookshelfItem]) -> BookshelfItem? {
        let path = url.standardizedFileURL.path
        guard let index = items.firstIndex(where: { $0.url.standardizedFileURL.path == path }) else { return nil }
        let target = index + offset
        return items.indices.contains(target) ? items[target] : nil
    }
}

/// シャッフルの順番を、本棚を開き直すまで固定するための乱数生成器。
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 本棚パネルの状態（表示中のフォルダ、選択中の項目、場所の履歴、並び順）。
@MainActor
@Observable
final class BookshelfModel {
    /// 表示中のフォルダ
    private(set) var place: URL?
    private(set) var items: [BookshelfItem] = []
    /// 選択中の項目（開いている本、または最後にクリックした項目）
    var selected: URL?
    /// 名前での絞り込み
    var filterText = ""
    private(set) var errorMessage: String?

    var order: FolderOrder {
        didSet {
            defaults.set(order.rawValue, forKey: "bookshelf.order")
            if order == .random { randomSeed = UInt64.random(in: 0...UInt64.max) }
            reloadItems()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var randomSeed: UInt64 = UInt64.random(in: 0...UInt64.max)
    @ObservationIgnored private var backStack: [URL] = []
    @ObservationIgnored private var forwardStack: [URL] = []
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        order = defaults.string(forKey: "bookshelf.order").flatMap(FolderOrder.init(rawValue:)) ?? .fileName
    }

    /// NeeView の既定のホーム（ピクチャフォルダ。なければホームフォルダ）
    static var homeURL: URL {
        let pictures = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return FileManager.default.fileExists(atPath: pictures.path) ? pictures : FileManager.default.homeDirectoryForCurrentUser
    }

    /// 絞り込み後の一覧
    var visibleItems: [BookshelfItem] {
        let text = filterText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return items }
        return items.filter { $0.name.localizedStandardContains(text) }
    }

    /// フォルダへ移動する。
    func move(to folder: URL, select: URL? = nil, recordHistory: Bool = true) {
        let folder = folder.standardizedFileURL
        if recordHistory, let place, place != folder {
            backStack.append(place)
            forwardStack.removeAll()
        }
        place = folder
        selected = select?.standardizedFileURL
        filterText = ""
        reloadItems()
        updateNavigation()
    }

    /// 本を開いたとき：その本の親フォルダを表示し、本を選択する
    func reveal(_ book: URL) {
        let book = book.standardizedFileURL
        let parent = book.deletingLastPathComponent()
        if place == parent {
            selected = book
        } else {
            move(to: parent, select: book)
        }
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let place { forwardStack.append(place) }
        move(to: previous, select: place, recordHistory: false)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let place { backStack.append(place) }
        move(to: next, recordHistory: false)
    }

    func goUp() {
        guard let place, place.path != "/" else { return }
        move(to: place.deletingLastPathComponent(), select: place)
    }

    func goHome() {
        move(to: Self.homeURL)
    }

    func reloadItems() {
        guard let place else {
            items = []
            return
        }
        do {
            items = try BookshelfListing.items(in: place, order: order, randomSeed: randomSeed)
            errorMessage = nil
        } catch {
            items = []
            errorMessage = "フォルダ「\(place.lastPathComponent)」を読み込めません。"
        }
    }

    /// 選択中の項目の前後。本棚の一覧が古い場合に備えて読み直してから探す。
    func neighbor(offset: Int) -> BookshelfItem? {
        guard let selected else { return nil }
        reloadItems()
        return BookshelfListing.neighbor(of: selected, offset: offset, in: items)
    }

    private func updateNavigation() {
        canGoBack = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
    }
}
