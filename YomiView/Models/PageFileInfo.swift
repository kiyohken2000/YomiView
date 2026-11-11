import Foundation

/// ページの元ファイルの情報（ファイル情報パネル用）。
struct PageFileInfo: @unchecked Sendable {
    var fileName: String
    /// ファイルのパス（アーカイブ内のページはアーカイブ内のパス）
    var filePath: String
    var creationDate: Date?
    var modificationDate: Date?
    /// バイト数
    var fileSize: Int64?
    /// アーカイブ・PDF の中のページなら、そのファイルのパス
    var archivePath: String?
    /// 読み込みに使った仕組み（「ZIP」「PDF」など）
    var archiver: String?
    /// PDF のページの大きさ（ポイント）
    var pdfPageSize: CGSize?
    /// ImageIO の画像プロパティ（kCGImageProperty*）
    var imageProperties: [String: Any] = [:]
    /// 画像の形式（UTI）
    var imageType: String?
}
