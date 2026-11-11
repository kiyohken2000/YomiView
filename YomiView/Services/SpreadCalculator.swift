import Foundation

/// 横長ページを分割したときの、読む順で何番目の半分か（NeeView の PagePosition.Part）
enum PagePart: Int, Equatable, Hashable {
    case first = 0
    case second = 1

    /// 画面上でどちらの半分か。右開きでは右半分から読む
    func side(direction: ReadingDirection) -> PageHalf {
        switch (self, direction) {
        case (.first, .rightToLeft), (.second, .leftToRight): return .right
        case (.first, .leftToRight), (.second, .rightToLeft): return .left
        }
    }
}

/// 画像の左半分 / 右半分
enum PageHalf: Equatable, Hashable {
    case left
    case right
}

/// 一度に表示するページの組（1ページまたは2ページ）。`pages` は読む順（若い番号が先）。
struct Spread: Equatable, Hashable {
    let pages: [Int]
    /// 横長ページを分割して表示するときの半分。分割しないなら nil
    var part: PagePart?

    init(pages: [Int], part: PagePart? = nil) {
        self.pages = pages
        self.part = part
    }

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
        /// 最後のページを単独で表示する（NeeView の IsSupportedSingleLastPage。既定オフ）
        var lastSingle = false
        /// 1ページ表示のとき、横長のページを左右に分割する（NeeView の IsSupportedDividePage。既定オフ）
        var dividePage = false
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
            return (0..<pageCount).flatMap { page in
                options.dividePage && isWide(page)
                    ? [Spread(pages: [page], part: .first), Spread(pages: [page], part: .second)]
                    : [Spread(pages: [page])]
            }
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
            // 最後のページを単独にするときは、最後のページと組ませない
            let nextIsSingleLast = options.lastSingle && next == pageCount - 1
            if !mustBeSingle(page), next < pageCount, !mustBeSingle(next), !nextIsSingleLast {
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

    /// 指定ページを含む組の位置。分割されたページでは `part` の半分（nil なら最初の半分）を選ぶ。
    static func spreadIndex(containing page: Int, part: PagePart? = nil, in spreads: [Spread]) -> Int? {
        spreads.firstIndex { $0.contains(page) && ($0.part == nil || part == nil || $0.part == part) }
            ?? spreads.firstIndex { $0.contains(page) }
    }
}
