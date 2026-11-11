import Foundation
import Observation

/// ブックマーク（本のパスと登録日時）。UserDefaults に保存する。
///
/// NeeView のブックマークはフォルダで階層を作れるが、YomiView は登録順の一覧のみ。
@MainActor
@Observable
final class BookmarkStore {
    static let shared = BookmarkStore(defaults: .standard)
    private static let key = "bookmarks"

    struct Bookmark: Codable, Equatable, Identifiable {
        var path: String
        var addedAt: Date

        var id: String { path }
        var url: URL { URL(fileURLWithPath: path) }
        var displayName: String { url.lastPathComponent }
    }

    /// 登録した順
    private(set) var bookmarks: [Bookmark]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = saved
        } else {
            bookmarks = []
        }
    }

    func contains(_ url: URL) -> Bool {
        let path = RecentBooksStore.normalizedPath(of: url)
        return bookmarks.contains { $0.path == path }
    }

    /// 登録されていなければ登録し、登録されていれば外す（NeeView の ToggleBookmark）
    func toggle(_ url: URL) {
        let path = RecentBooksStore.normalizedPath(of: url)
        if bookmarks.contains(where: { $0.path == path }) {
            bookmarks.removeAll { $0.path == path }
        } else {
            bookmarks.append(Bookmark(path: path, addedAt: Date()))
        }
        save()
    }

    func remove(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.path == bookmark.path }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
