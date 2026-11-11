import CoreGraphics
import Foundation
import ZIPFoundation

/// ZIP / CBZ アーカイブ内の画像エントリをページとして提供する。
///
/// アーカイブ内のサブフォルダの画像も含め、パス全体を自然順で並べる。
/// `__MACOSX/` 配下と、`.` で始まるファイル・フォルダは除外する。
final class ZipPageProvider: PageProvider, @unchecked Sendable {
    let title: String
    let pages: [PageItem]

    /// ZIPFoundation の Archive は同時アクセスに対応していないため、lock で直列化する。
    private let lock = NSLock()
    private let archive: Archive
    private let entries: [Entry]

    init(archiveURL: URL) throws {
        title = archiveURL.deletingPathExtension().lastPathComponent
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            throw BookError.unreadableArchive(archiveURL.lastPathComponent)
        }

        let candidates: [(path: String, entry: Entry)] = archive.compactMap { entry in
            guard entry.type == .file else { return nil }
            let path = Self.decodedPath(of: entry)
            guard Self.isPageEntryPath(path) else { return nil }
            return (path, entry)
        }
        let sorted = candidates.sorted { NaturalSort.areInIncreasingOrder($0.path, $1.path) }
        guard !sorted.isEmpty else {
            throw BookError.noImages(archiveURL.lastPathComponent)
        }

        self.archive = archive
        entries = sorted.map(\.entry)
        pages = sorted.enumerated().map { index, item in
            PageItem(
                index: index,
                name: (item.path as NSString).lastPathComponent,
                kind: .archiveEntry(path: item.path)
            )
        }
    }

    func loadImage(at index: Int, maxPixelSize: Int) throws -> CGImage {
        guard entries.indices.contains(index) else {
            throw BookError.pageOutOfRange(index)
        }
        let name = pages[index].name
        var data = Data()
        lock.lock()
        defer { lock.unlock() }
        do {
            _ = try archive.extract(entries[index], skipCRC32: true) { chunk in
                data.append(chunk)
            }
        } catch {
            throw BookError.imageDecodeFailed(name)
        }
        return try ImageLoading.downsample(data: data, maxPixelSize: maxPixelSize, name: name)
    }

    /// ページとして扱うエントリのパスか。
    static func isPageEntryPath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let last = components.last else { return false }
        if components.contains(where: { $0 == "__MACOSX" || $0.hasPrefix(".") }) {
            return false
        }
        return ImageLoading.isImageFileName(String(last))
    }

    /// エントリのパスを文字列にする。
    ///
    /// UTF-8 として正しければ UTF-8、そうでなければ Shift_JIS（日本語環境の Windows で作られた ZIP に多い）、
    /// どちらでもなければ ZIPFoundation の既定（UTF-8 フラグがなければ CP437）を使う。
    static func decodedPath(of entry: Entry) -> String {
        let utf8 = entry.path(using: .utf8)
        if !utf8.isEmpty { return utf8 }
        let sjis = entry.path(using: .shiftJIS)
        if !sjis.isEmpty { return sjis }
        return entry.path
    }
}
