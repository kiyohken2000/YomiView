import CoreGraphics
import Foundation
import ImageIO

/// フォルダ内の画像ファイルをページとして提供する。隠しファイルは含めない。
///
/// 既定ではフォルダ直下の画像だけを読む。`recursive` のときはサブフォルダの画像も読み、
/// フォルダからの相対パス全体を自然順で並べる（NeeView の「サブフォルダーを読み込む」）。
final class FolderPageProvider: PageProvider {
    let title: String
    let pages: [PageItem]
    /// サブフォルダの画像も読み込んでいるか
    let isRecursive: Bool

    private static let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]

    init(folderURL: URL, recursive: Bool = false) throws {
        title = folderURL.lastPathComponent
        isRecursive = recursive
        let contents: [URL]
        if recursive {
            guard let enumerator = FileManager.default.enumerator(
                at: folderURL, includingPropertiesForKeys: Self.resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                throw BookError.unreadableFolder(folderURL.lastPathComponent)
            }
            contents = enumerator.compactMap { $0 as? URL }
            // 列挙できないフォルダそのものは、直下の読み込みで判定する
            if contents.isEmpty, (try? FileManager.default.contentsOfDirectory(atPath: folderURL.path)) == nil {
                throw BookError.unreadableFolder(folderURL.lastPathComponent)
            }
        } else {
            do {
                contents = try FileManager.default.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: Self.resourceKeys,
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
                )
            } catch {
                throw BookError.unreadableFolder(folderURL.lastPathComponent)
            }
        }

        let basePath = folderURL.standardizedFileURL.path
        let images: [(path: String, url: URL, values: URLResourceValues?)] = contents.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys))
            guard values?.isRegularFile == true, ImageLoading.isImageFileName(url.lastPathComponent) else { return nil }
            return (Self.relativePath(of: url, base: basePath), url, values)
        }
        let sorted = images.enumerated().sorted { NaturalSort.areInIncreasingOrder($0.element.path, $1.element.path) }
        guard !sorted.isEmpty else {
            throw BookError.noImages(folderURL.lastPathComponent)
        }
        pages = sorted.enumerated().map { index, item in
            PageItem(
                index: index, name: item.element.path, kind: .file(item.element.url), entryIndex: item.offset,
                modificationDate: item.element.values?.contentModificationDate,
                fileSize: item.element.values?.fileSize.map(Int64.init)
            )
        }
    }

    /// フォルダからの相対パス（直下ならファイル名）
    private static func relativePath(of url: URL, base: String) -> String {
        let path = url.standardizedFileURL.path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : url.lastPathComponent
    }

    func loadImage(at index: Int, maxPixelSize: Int) throws -> PageImage {
        guard pages.indices.contains(index), case .file(let url) = pages[index].kind else {
            throw BookError.pageOutOfRange(index)
        }
        return try ImageLoading.loadPage(url: url, maxPixelSize: maxPixelSize)
    }

    func fileInfo(at index: Int) throws -> PageFileInfo {
        guard pages.indices.contains(index), case .file(let url) = pages[index].kind else {
            throw BookError.pageOutOfRange(index)
        }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
        var info = PageFileInfo(
            fileName: url.lastPathComponent,
            filePath: url.path,
            creationDate: values?.creationDate,
            modificationDate: values?.contentModificationDate,
            fileSize: values?.fileSize.map(Int64.init)
        )
        if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) {
            (info.imageType, info.imageProperties) = ImageLoading.properties(of: source)
        }
        return info
    }
}
