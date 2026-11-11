import Foundation

/// ファイル名の自然順ソート（`page2.jpg` が `page10.jpg` より前に来る）。Finder と同じ `localizedStandardCompare` を使う。
enum NaturalSort {
    static func areInIncreasingOrder(_ lhs: String, _ rhs: String) -> Bool {
        let result = lhs.localizedStandardCompare(rhs)
        if result == .orderedSame {
            // 大文字小文字などだけが違う場合も順序を一意に決める
            return lhs < rhs
        }
        return result == .orderedAscending
    }

    static func sorted(_ names: [String]) -> [String] {
        names.sorted(by: areInIncreasingOrder)
    }
}
