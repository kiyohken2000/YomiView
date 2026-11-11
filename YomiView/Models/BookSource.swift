import Foundation
import UniformTypeIdentifiers

/// 本の種類。URL から判定する。
enum BookSource: Equatable {
    /// 画像ファイルを直下に持つフォルダ
    case folder(URL)
    /// ZIP または CBZ アーカイブ
    case archive(URL)

    /// アーカイブとして扱う拡張子（小文字）
    static let archiveExtensions: Set<String> = ["zip", "cbz"]

    var url: URL {
        switch self {
        case .folder(let url), .archive(let url):
            return url
        }
    }

    /// URL から本の種類を判定する。対応していない形式なら `BookError.unsupportedFormat` を投げる。
    static func detect(_ url: URL) throws -> BookSource {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw BookError.notFound(url.lastPathComponent)
        }
        if isDirectory.boolValue {
            return .folder(url)
        }
        if archiveExtensions.contains(url.pathExtension.lowercased()) {
            return .archive(url)
        }
        throw BookError.unsupportedFormat(url.lastPathComponent)
    }

    /// 対応する PageProvider を作る。
    func makeProvider() throws -> PageProvider {
        switch self {
        case .folder(let url):
            return try FolderPageProvider(folderURL: url)
        case .archive(let url):
            return try ZipPageProvider(archiveURL: url)
        }
    }
}

/// 本を開く・ページを読むときのエラー。
enum BookError: LocalizedError, Equatable {
    case notFound(String)
    case unsupportedFormat(String)
    case unreadableArchive(String)
    case noImages(String)
    case pageOutOfRange(Int)
    case imageDecodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let name):
            return "「\(name)」が見つかりません。"
        case .unsupportedFormat(let name):
            return "「\(name)」は対応していない形式です。フォルダ、ZIP、CBZ を開けます。"
        case .unreadableArchive(let name):
            return "「\(name)」を読み込めません。ファイルが壊れている可能性があります。"
        case .noImages(let name):
            return "「\(name)」には表示できる画像がありません。"
        case .pageOutOfRange(let index):
            return "ページ \(index + 1) は存在しません。"
        case .imageDecodeFailed(let name):
            return "「\(name)」を画像として読み込めません。"
        }
    }
}

extension BookSource {
    /// ファイル選択ダイアログで選べるファイルの種類（フォルダは canChooseDirectories で選ぶ）
    static var openPanelContentTypes: [UTType] {
        var types: [UTType] = [.zip]
        if let cbz = UTType(filenameExtension: "cbz") {
            types.append(cbz)
        }
        return types
    }
}
