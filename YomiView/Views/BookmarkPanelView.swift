import SwiftUI

/// ブックマークパネル。登録した本を登録順に並べ、クリックで開く。右クリックで削除。
struct BookmarkPanelView: View {
    let bookmarks: BookmarkStore
    let viewModel: ReaderViewModel

    var body: some View {
        if bookmarks.bookmarks.isEmpty {
            Text("ブックマークはありません。アドレスバーの ☆ か ⌘D で登録できます。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.grayText)
                .padding(8)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(bookmarks.bookmarks) { bookmark in
                        PanelListRow(
                            title: bookmark.displayName,
                            subtitle: bookmark.url.deletingLastPathComponent().path,
                            isSelected: viewModel.bookURL.map(RecentBooksStore.normalizedPath(of:)) == bookmark.path,
                            action: { viewModel.open(bookmark.url, failure: .notice) }
                        ) {
                            ThumbnailView(store: BookThumbnails.shared, key: bookmark.path, placeholderSymbol: "book.closed")
                                .frame(width: 48, height: 48)
                        }
                        .contextMenu {
                            Button("ブックマークから削除") { bookmarks.remove(bookmark) }
                        }
                    }
                }
            }
        }
    }
}
