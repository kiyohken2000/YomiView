import Foundation

/// 一度に表示するページの組（1ページまたは2ページ）。`pages` は読む順（若い番号が先）。
struct Spread: Equatable, Hashable {
    let pages: [Int]

    var first: Int { pages[0] }
    var last: Int { pages[pages.count - 1] }

    func contains(_ page: Int) -> Bool { pages.contains(page) }
}

/// 見開きのページの組み合わせを決める。副作用のない関数だけを持つ。
enum SpreadCalculator {
    struct Options: Equatable {
        /// 表紙（1ページ目）を単独で表示する
        var coverSingle = true
        /// 横長のページを単独で表示する
        var landscapeSingle = true
    }

    /// 本全体のページの組を、読む順に返す。
    ///
    /// - Parameters:
    ///   - pageCount: ページ数
    ///   - mode: 1ページ表示なら全ページが単独になる
    ///   - isWide: そのページが横長か。まだ分からないページは false を返す
    static func spreads(
        pageCount: Int,
        mode: ViewMode,
        options: Options = Options(),
        isWide: (Int) -> Bool = { _ in false }
    ) -> [Spread] {
        guard pageCount > 0 else { return [] }
        guard mode == .spread else {
            return (0..<pageCount).map { Spread(pages: [$0]) }
        }

        func mustBeSingle(_ page: Int) -> Bool {
            options.landscapeSingle && isWide(page)
        }

        var result: [Spread] = []
        var page = 0
        if options.coverSingle {
            result.append(Spread(pages: [0]))
            page = 1
        }
        while page < pageCount {
            let next = page + 1
            if !mustBeSingle(page), next < pageCount, !mustBeSingle(next) {
                result.append(Spread(pages: [page, next]))
                page += 2
            } else {
                // 横長のページ、または組む相手がいない（最後に余った）ページは単独
                result.append(Spread(pages: [page]))
                page += 1
            }
        }
        return result
    }

    /// 画面に左から並べる順にページを返す。右開きでは読む順と逆になる。
    static func displayOrder(of spread: Spread, direction: ReadingDirection) -> [Int] {
        direction == .rightToLeft ? spread.pages.reversed() : spread.pages
    }

    /// 指定ページを含む組の位置。
    static func spreadIndex(containing page: Int, in spreads: [Spread]) -> Int? {
        spreads.firstIndex { $0.contains(page) }
    }
}
