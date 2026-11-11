import CoreGraphics
import Foundation
import PDFKit

/// PDF の各ページを画像として提供する。PDFKit で開き、要求された大きさで描画する。
final class PDFPageProvider: PageProvider, @unchecked Sendable {
    /// ページのサイズ（ポイント）に対する描画倍率の上限。小さなページを巨大な画像にしないため。
    static let maxRenderScale: CGFloat = 4

    let title: String
    let pages: [PageItem]

    /// PDFDocument は同時アクセスに対応していないため、lock で直列化する。
    private let lock = NSLock()
    private let document: PDFDocument
    private let pdfURL: URL

    init(pdfURL: URL) throws {
        title = pdfURL.deletingPathExtension().lastPathComponent
        guard let document = PDFDocument(url: pdfURL), !document.isLocked else {
            throw BookError.unreadablePDF(pdfURL.lastPathComponent)
        }
        guard document.pageCount > 0 else {
            throw BookError.noImages(pdfURL.lastPathComponent)
        }
        self.document = document
        self.pdfURL = pdfURL
        pages = (0..<document.pageCount).map { index in
            let label = document.page(at: index)?.label ?? "\(index + 1)"
            return PageItem(index: index, name: label, kind: .pdfPage(index))
        }
    }

    func fileInfo(at index: Int) throws -> PageFileInfo {
        guard pages.indices.contains(index) else { throw BookError.pageOutOfRange(index) }
        lock.lock()
        let page = document.page(at: index)
        let box = page?.bounds(for: .cropBox) ?? .zero
        let rotated = ((page?.rotation ?? 0) / 90) % 2 != 0
        lock.unlock()
        let values = try? pdfURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
        return PageFileInfo(
            fileName: pages[index].name,
            filePath: "\(pdfURL.lastPathComponent) > \(pages[index].name)",
            creationDate: values?.creationDate,
            modificationDate: values?.contentModificationDate,
            fileSize: values?.fileSize.map(Int64.init),
            archivePath: pdfURL.path,
            archiver: "PDF",
            pdfPageSize: rotated ? CGSize(width: box.height, height: box.width) : box.size
        )
    }

    func loadImage(at index: Int, maxPixelSize: Int) throws -> PageImage {
        guard pages.indices.contains(index) else {
            throw BookError.pageOutOfRange(index)
        }
        lock.lock()
        defer { lock.unlock() }
        guard let page = document.page(at: index), let cgPage = page.pageRef else {
            throw BookError.imageDecodeFailed(pages[index].name)
        }

        // 回転を反映した、表示上のページサイズ（ポイント）
        let box = page.bounds(for: .cropBox)
        let isRotated = (page.rotation / 90) % 2 != 0
        let pointSize = isRotated ? CGSize(width: box.height, height: box.width) : box.size
        let longSide = max(pointSize.width, pointSize.height)
        guard longSide > 0 else {
            throw BookError.imageDecodeFailed(pages[index].name)
        }

        let scale = min(CGFloat(max(1, maxPixelSize)) / longSide, Self.maxRenderScale)
        let width = max(1, Int((pointSize.width * scale).rounded()))
        let height = max(1, Int((pointSize.height * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw BookError.imageDecodeFailed(pages[index].name)
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: CGFloat(width) / pointSize.width, y: CGFloat(height) / pointSize.height)
        // getDrawingTransform は拡大しないため、倍率は上で掛け、ここでは回転と位置合わせだけを行う
        context.concatenate(cgPage.getDrawingTransform(
            .cropBox, rect: CGRect(origin: .zero, size: pointSize), rotate: 0, preserveAspectRatio: true
        ))
        context.drawPDFPage(cgPage)

        guard let image = context.makeImage() else {
            throw BookError.imageDecodeFailed(pages[index].name)
        }
        return PageImage(cgImage: image, pointSize: pointSize)
    }
}
