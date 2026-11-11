import Foundation

/// ページ1枚の情報。
struct PageItem: Equatable, Identifiable {
    /// ページの取得元
    enum Kind: Equatable {
        /// フォルダ内の画像ファイル
        case file(URL)
        /// アーカイブ内のエントリ（アーカイブ内のパス）
        case archiveEntry(path: String)
        /// PDF のページ（0 始まり）
        case pdfPage(Int)
    }

    /// 本の中での 0 始まりの位置
    let index: Int
    /// 表示名（ファイル名）
    let name: String
    let kind: Kind

    var id: Int { index }
}
