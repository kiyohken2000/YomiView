import CoreGraphics
import Foundation
import ImageIO

/// フォルダ直下の画像ファイルをページとして提供する。サブフォルダと隠しファイルは含めない。
final class FolderPageProvider: PageProvider {
    let title: String
    let pages: [PageItem]

    init(folderURL: URL) throws {
        title = folderURL.lastPathComponent
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            throw BookError.unreadableFolder(folderURL.lastPathComponent)
        }

        let imageURLs = contents.filter { url in
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            return isFile && ImageLoading.isImageFileName(url.lastPathComponent)
        }
        let sorted = imageURLs.sorted { NaturalSort.areInIncreasingOrder($0.lastPathComponent, $1.lastPathComponent) }
        guard !sorted.isEmpty else {
            throw BookError.noImages(folderURL.lastPathComponent)
        }
        pages = sorted.enumerated().map { index, url in
            PageItem(index: index, name: url.lastPathComponent, kind: .file(url))
        }
    }

    func loadImage(at index: Int, maxPixelSize: Int) throws -> PageImage {
        guard pages.indices.contains(index), case .file(let url) = pages[index].kind else {
            throw BookError.pageOutOfRange(index)
        }
        return PageImage(cgImage: try ImageLoading.downsample(url: url, maxPixelSize: maxPixelSize))
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
