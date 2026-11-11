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
    private(set) var index: Int
    /// 表示名（ファイル名）
    let name: String
    let kind: Kind
    /// 取得元での並び（フォルダの列挙順、ZIP の格納順、PDF のページ順）。並び順「登録」で使う
    var entryIndex: Int
    /// 更新日時（並び順「日付」で使う）
    var modificationDate: Date?
    /// ファイルサイズ（並び順「サイズ」で使う）
    var fileSize: Int64?

    init(index: Int, name: String, kind: Kind, entryIndex: Int? = nil, modificationDate: Date? = nil, fileSize: Int64? = nil) {
        self.index = index
        self.name = name
        self.kind = kind
        self.entryIndex = entryIndex ?? index
        self.modificationDate = modificationDate
        self.fileSize = fileSize
    }

    var id: Int { index }

    /// 並べ替えに使うパス（アーカイブ内のパス、またはファイル名）
    var sortPath: String {
        switch kind {
        case .archiveEntry(let path): return path
        case .file, .pdfPage: return name
        }
    }

    /// 同じページを別の位置に置き直す
    func reindexed(_ index: Int) -> PageItem {
        var item = self
        item.index = index
        return item
    }
}
