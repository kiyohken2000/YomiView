import Foundation

/// ページの並び順（NeeView の PageSortMode。表示名も NeeView に合わせる）
enum PageSortMode: String, CaseIterable, Identifiable {
    case fileName
    case fileNameDescending
    case fileType
    case fileTypeDescending
    case timeStamp
    case timeStampDescending
    case size
    case sizeDescending
    case entry
    case entryDescending
    case random

    var id: String { rawValue }

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
        case .entry: return "登録↑"
        case .entryDescending: return "登録↓"
        case .random: return "シャッフル"
        }
    }
}

/// ページを並び順に従って並べ替える。副作用のない関数だけを持つ。
///
/// NeeView の BookPageSort に合わせ、名前以外の並び順で同じ値のページは名前の自然順で並べる。
enum PageSorter {
    static func sorted(_ pages: [PageItem], mode: PageSortMode, seed: UInt64 = 0) -> [PageItem] {
        let byName: (PageItem, PageItem) -> Bool = { NaturalSort.areInIncreasingOrder($0.sortPath, $1.sortPath) }
        func then<T: Comparable>(_ key: (PageItem) -> T, descending: Bool) -> [PageItem] {
            pages.sorted { a, b in
                let ka = key(a), kb = key(b)
                if ka != kb { return descending ? ka > kb : ka < kb }
                return byName(a, b)
            }
        }
        switch mode {
        case .fileName:
            return pages.sorted(by: byName)
        case .fileNameDescending:
            return pages.sorted { byName($1, $0) }
        case .fileType:
            return then({ fileType(of: $0) }, descending: false)
        case .fileTypeDescending:
            return then({ fileType(of: $0) }, descending: true)
        case .timeStamp:
            return then({ $0.modificationDate ?? .distantPast }, descending: false)
        case .timeStampDescending:
            return then({ $0.modificationDate ?? .distantPast }, descending: true)
        case .size:
            return then({ $0.fileSize ?? 0 }, descending: false)
        case .sizeDescending:
            return then({ $0.fileSize ?? 0 }, descending: true)
        case .entry:
            return pages.sorted { $0.entryIndex < $1.entryIndex }
        case .entryDescending:
            return pages.sorted { $0.entryIndex > $1.entryIndex }
        case .random:
            // 名前順にしてから混ぜることで、同じ seed なら同じ並びになるようにする
            var generator = SeededGenerator(seed: seed)
            return pages.sorted(by: byName).shuffled(using: &generator)
        }
    }

    /// 種類（拡張子、小文字）
    private static func fileType(of page: PageItem) -> String {
        (page.name as NSString).pathExtension.lowercased()
    }
}

/// 元の PageProvider のページを並べ替えて提供する。画像の読み込みは元の PageProvider に任せる。
final class SortedPageProvider: PageProvider, @unchecked Sendable {
    let base: PageProvider
    let mode: PageSortMode
    let pages: [PageItem]
    /// 並べ替えた後の位置 → 元の位置
    private let baseIndices: [Int]

    var title: String { base.title }

    init(base: PageProvider, mode: PageSortMode, seed: UInt64 = 0) {
        self.base = base
        self.mode = mode
        let sorted = PageSorter.sorted(base.pages, mode: mode, seed: seed)
        baseIndices = sorted.map(\.index)
        pages = sorted.enumerated().map { $1.reindexed($0) }
    }

    func loadImage(at index: Int, maxPixelSize: Int) throws -> PageImage {
        guard baseIndices.indices.contains(index) else { throw BookError.pageOutOfRange(index) }
        return try base.loadImage(at: baseIndices[index], maxPixelSize: maxPixelSize)
    }

    func fileInfo(at index: Int) throws -> PageFileInfo {
        guard baseIndices.indices.contains(index) else { throw BookError.pageOutOfRange(index) }
        return try base.fileInfo(at: baseIndices[index])
    }
}
