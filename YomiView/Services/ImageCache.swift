import Foundation

/// ページ画像の LRU キャッシュ。件数に上限を設け、最も長く使われていないものから捨てる。
///
/// 同じページでも読み込んだ大きさが足りなければ「なし」として扱い、呼び出し側に読み直させる。
final class ImageCache: @unchecked Sendable {
    struct Entry {
        let image: PageImage
        /// 読み込んだときに要求した長辺の上限（ピクセル）
        let maxPixelSize: Int

        /// `pixelSize` での表示に十分な大きさか。元画像が要求より小さかった場合は、それ以上大きくならないので十分とみなす
        func isSufficient(for pixelSize: Int) -> Bool {
            let longSide = max(image.cgImage.width, image.cgImage.height)
            return maxPixelSize >= pixelSize || longSide < maxPixelSize
        }
    }

    let capacity: Int
    private let lock = NSLock()
    private var entries: [Int: Entry] = [:]
    /// 使われた順（末尾が最新）
    private var order: [Int] = []

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    /// 大きさを問わず、キャッシュにある画像を返す（使用済みとして記録する）。
    func image(for page: Int) -> PageImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[page] else { return nil }
        touch(page)
        return entry.image
    }

    /// `pixelSize` での表示に十分な大きさの画像があるか。
    func contains(_ page: Int, sufficientFor pixelSize: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[page]?.isSufficient(for: pixelSize) ?? false
    }

    func insert(_ image: PageImage, for page: Int, maxPixelSize: Int) {
        lock.lock()
        defer { lock.unlock() }
        entries[page] = Entry(image: image, maxPixelSize: maxPixelSize)
        touch(page)
        while order.count > capacity {
            let evicted = order.removeFirst()
            entries[evicted] = nil
        }
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries = [:]
        order = []
    }

    /// キャッシュにあるページ（古い順）
    var pages: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return order
    }

    private func touch(_ page: Int) {
        order.removeAll { $0 == page }
        order.append(page)
    }
}
