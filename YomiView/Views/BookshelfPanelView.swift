import SwiftUI

/// 本棚パネル（NeeView/SidePanels/Bookshelf/FolderListView.xaml の構成）。
/// クリックで本を開き、フォルダをダブルクリックするとその中へ移動する。
struct BookshelfPanelView: View {
    @Bindable var bookshelf: BookshelfModel
    let viewModel: ReaderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            placeRow
            toolbar
            sortMenu
            searchBox
            list
        }
        .onAppear {
            if bookshelf.place == nil {
                if let book = viewModel.bookURL { bookshelf.reveal(book) } else { bookshelf.goHome() }
            }
        }
    }

    private var placeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color(hex: 0xF8D775))
            Text(bookshelf.place?.path ?? "")
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(Theme.foreground)
            Spacer(minLength: 4)
            Text("\(bookshelf.visibleItems.count)")
                .foregroundStyle(Theme.foreground)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button { bookshelf.goHome() } label: { Image(systemName: "house.fill") }
                .help("ホームに移動")
            Button { bookshelf.goBack() } label: { Image(systemName: "arrow.left") }
                .help("戻る")
                .disabled(!bookshelf.canGoBack)
            Button { bookshelf.goForward() } label: { Image(systemName: "arrow.right") }
                .help("進む")
                .disabled(!bookshelf.canGoForward)
            Button { bookshelf.goUp() } label: { Image(systemName: "arrow.up") }
                .help("上の階層へ")
            Button { bookshelf.reloadItems() } label: { Image(systemName: "arrow.clockwise") }
                .help("更新")
            Spacer()
        }
        .buttonStyle(IconButtonStyle())
        .font(.system(size: 14, weight: .semibold))
        .padding(.horizontal, 4)
    }

    /// 並び順（NeeView と同じく、ツールバーの下に「名前↑ ⌄」の形で置く）
    private var sortMenu: some View {
        Menu {
            Picker("並び順", selection: $bookshelf.order) {
                ForEach(FolderOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text("\(bookshelf.order.label) \(Image(systemName: "chevron.down"))")
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 10)
        .help("並び順")
    }

    private var searchBox: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.grayText)
            TextField("", text: $bookshelf.filterText, prompt: Text("名前で絞り込み").foregroundStyle(Theme.grayText))
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.foreground)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 6)
        .frame(height: 24)
        .background(Theme.textBoxBackground)
        .overlay(Rectangle().strokeBorder(Theme.textBoxBorder, lineWidth: 1))
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var list: some View {
        if let message = bookshelf.errorMessage {
            note(message)
        } else if bookshelf.visibleItems.isEmpty {
            note("項目はありません")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(bookshelf.visibleItems) { item in
                            BookshelfRow(
                                item: item,
                                isSelected: bookshelf.selected == item.url.standardizedFileURL,
                                onOpen: {
                                    bookshelf.selected = item.url.standardizedFileURL
                                    viewModel.open(item.url, failure: .notice)
                                },
                                onEnter: {
                                    if item.isFolder { bookshelf.move(to: item.url) }
                                }
                            )
                            .id(item.url.standardizedFileURL)
                        }
                    }
                }
                .onChange(of: bookshelf.selected) { _, selected in
                    if let selected { withAnimation { proxy.scrollTo(selected) } }
                }
                .onAppear {
                    if let selected = bookshelf.selected { proxy.scrollTo(selected, anchor: .center) }
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.grayText)
            .padding(8)
    }
}

/// 本棚の1行：アイコン、日付、名前。
private struct BookshelfRow: View {
    let item: BookshelfItem
    let isSelected: Bool
    let onOpen: () -> Void
    let onEnter: () -> Void

    @State private var isHovered = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 8) {
            // フォルダも本として開けるなら表紙のサムネイル、開けなければフォルダのアイコン
            Group {
                if item.isFolder && BookThumbnails.shared.hasFailed(item.url.path) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color(hex: 0xF8D775))
                } else {
                    ThumbnailView(store: BookThumbnails.shared, key: item.url.path, placeholderSymbol: icon)
                }
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dateFormatter.string(from: item.modified))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.grayText)
                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if BookmarkStore.shared.contains(item.url) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.bookmarkIcon)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isSelected ? Theme.itemSelected : (isHovered ? Theme.itemMouseOver : .clear))
        .overlay {
            if isSelected || isHovered {
                Rectangle().strokeBorder(Theme.accent.opacity(isSelected ? 1 : 0.65), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .gesture(TapGesture(count: 2).onEnded(onEnter).exclusively(before: TapGesture().onEnded(onOpen)))
        .help(item.url.path)
    }

    private var icon: String {
        switch item.kind {
        case .folder: return "folder.fill"
        case .archive: return "doc.zipper"
        case .pdf: return "doc.richtext"
        }
    }
}
