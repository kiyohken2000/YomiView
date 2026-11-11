import CoreGraphics
import Foundation
import Observation

/// サムネイルの長辺（ピクセル）。NeeView の既定値
enum ThumbnailSize {
    static let pixels = 256
}

/// サムネイルを必要になった分だけバックグラウンドで作り、件数上限つき LRU で保持する。
///
/// 一覧に表示された項目から `request` され、後から要求されたもの（今見ている所）を先に作る。
/// NeeView の既定に合わせ、サムネイルの幅は 256px、保持数はページ 100 件・本 200 件。
@MainActor
@Observable
final class ThumbnailStore<Key: Hashable & Sendable> {
    typealias Loader = @Sendable (Key) throws -> CGImage

    /// 中身が変わるたびに増える（View の更新用）
    private(set) var revision = 0

    @ObservationIgnored let capacity: Int
    @ObservationIgnored private var loader: Loader
    @ObservationIgnored private var images: [Key: CGImage] = [:]
    @ObservationIgnored private var order: [Key] = []
    @ObservationIgnored private var failed: Set<Key> = []
    @ObservationIgnored private var queue: [Key] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    /// 読み込み元を差し替えたら古い結果を捨てるための世代番号
    @ObservationIgnored private var generation = 0

    init(capacity: Int, loader: @escaping Loader) {
        self.capacity = capacity
        self.loader = loader
    }

    func image(for key: Key) -> CGImage? {
        _ = revision
        return images[key]
    }

    func hasFailed(_ key: Key) -> Bool {
        _ = revision
        return failed.contains(key)
    }

    /// サムネイルを要求する。すでにあるもの・失敗したものは何もしない。
    func request(_ key: Key) {
        guard images[key] == nil, !failed.contains(key) else {
            touch(key)
            return
        }
        queue.removeAll { $0 == key }
        queue.append(key)
        if task == nil {
            task = Task { [weak self] in await self?.run() }
        }
    }

    /// 画面から消えた項目の要求を取り消す
    func cancel(_ key: Key) {
        queue.removeAll { $0 == key }
    }

    /// 読み込み元を差し替え、保持しているサムネイルを捨てる（別の本を開いたとき）
    func reset(loader: @escaping Loader) {
        self.loader = loader
        generation += 1
        images = [:]
        order = []
        failed = []
        queue = []
        revision += 1
    }

    var count: Int { images.count }

    private func run() async {
        defer { task = nil }
        while let key = queue.popLast() {
            guard images[key] == nil, !failed.contains(key) else { continue }
            let loader = self.loader
            let generation = self.generation
            let result = await Task.detached(priority: .utility) { Result { try loader(key) } }.value
            guard generation == self.generation else { continue }
            switch result {
            case .success(let image):
                images[key] = image
                touch(key)
                while order.count > capacity {
                    images[order.removeFirst()] = nil
                }
            case .failure:
                failed.insert(key)
            }
            revision += 1
        }
    }

    private func touch(_ key: Key) {
        guard images[key] != nil else { return }
        order.removeAll { $0 == key }
        order.append(key)
    }
}

/// 本（フォルダ / ZIP / PDF）の表紙のサムネイル。本棚と履歴で共有する。
enum BookThumbnails {
    @MainActor static let shared = ThumbnailStore<String>(capacity: 200) { path in
        let provider = try BookSource.detect(URL(fileURLWithPath: path)).makeProvider()
        return try provider.loadImage(at: 0, maxPixelSize: ThumbnailSize.pixels).cgImage
    }
}
