import Foundation
import Observation

/// 最近開いた本と、本ごとの読書位置・見開き設定。UserDefaults に保存する。
@MainActor
@Observable
final class RecentBooksStore {
    static let shared = RecentBooksStore(defaults: .standard)
    /// 保持する件数の上限
    static let maxCount = 20
    private static let key = "recentBooks"

    struct Entry: Codable, Equatable, Identifiable {
        /// 本のパス（フォルダ / ZIP / CBZ / PDF）
        var path: String
        /// 最後に読んだページ（0 始まり）
        var lastPage: Int
        /// 手動で選んだ表示モード。nil なら自動（ウィンドウの形で決める）
        var viewMode: ViewMode?

        var id: String { path }
        var url: URL { URL(fileURLWithPath: path) }
        var displayName: String { url.lastPathComponent }
    }

    /// 新しく開いた順
    private(set) var entries: [Entry]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Array(saved.prefix(Self.maxCount))
        } else {
            entries = []
        }
    }

    /// 同じ本を同じキーで扱うため、パスを正規化する
    static func normalizedPath(of url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    func entry(for url: URL) -> Entry? {
        let path = Self.normalizedPath(of: url)
        return entries.first { $0.path == path }
    }

    /// 本を開いたことを記録し、先頭に移す。保存済みの位置があればそれを返す。
    @discardableResult
    func recordOpen(_ url: URL) -> Entry {
        let path = Self.normalizedPath(of: url)
        let entry = entries.first { $0.path == path } ?? Entry(path: path, lastPage: 0, viewMode: nil)
        entries.removeAll { $0.path == path }
        entries.insert(entry, at: 0)
        if entries.count > Self.maxCount {
            entries.removeLast(entries.count - Self.maxCount)
        }
        save()
        return entry
    }

    /// 読書位置と見開き設定を更新する。記録にない本は何もしない。
    func updatePosition(of url: URL, page: Int, viewMode: ViewMode?) {
        let path = Self.normalizedPath(of: url)
        guard let index = entries.firstIndex(where: { $0.path == path }) else { return }
        guard entries[index].lastPage != page || entries[index].viewMode != viewMode else { return }
        entries[index].lastPage = page
        entries[index].viewMode = viewMode
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
