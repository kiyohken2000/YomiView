import SwiftUI

/// 履歴パネル。最近開いた本を新しい順に表示し、クリックで開く。
struct HistoryPanelView: View {
    let recentBooks: RecentBooksStore
    let viewModel: ReaderViewModel

    var body: some View {
        if recentBooks.entries.isEmpty {
            Text("履歴はありません")
                .font(.system(size: 12))
                .foregroundStyle(Theme.grayText)
                .padding(8)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(recentBooks.entries) { entry in
                        PanelListRow(
                            title: entry.displayName,
                            subtitle: entry.url.deletingLastPathComponent().path,
                            isSelected: viewModel.bookURL.map(RecentBooksStore.normalizedPath(of:)) == entry.path,
                            action: { viewModel.open(entry.url) }
                        ) {
                            ThumbnailView(store: BookThumbnails.shared, key: entry.path, placeholderSymbol: "book.closed")
                                .frame(width: 48, height: 48)
                        }
                    }
                }
            }
        }
    }
}

/// パネルの一覧の1行。マウスを乗せる・選択するとアクセント色の背景になる（NeeView の Item.* の配色）。
struct PanelListRow<Leading: View>: View {
    let title: String
    var subtitle: String?
    var isSelected = false
    var action: () -> Void
    @ViewBuilder var leading: Leading

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.grayText)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isSelected ? Theme.itemSelected : (isHovered ? Theme.itemMouseOver : .clear))
        .overlay {
            if isSelected || isHovered {
                Rectangle().strokeBorder(Theme.accent.opacity(isSelected ? 1 : 0.65), lineWidth: 1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(hex: 0x888888, opacity: 0x22 / 255)).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
    }
}

extension PanelListRow where Leading == EmptyView {
    init(title: String, subtitle: String? = nil, isSelected: Bool = false, action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, isSelected: isSelected, action: action) { EmptyView() }
    }
}
