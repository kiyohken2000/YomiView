import SwiftUI

/// ページリストパネル（NeeView/SidePanels/PageList）。ページのサムネイルと名前を並べ、クリックでそのページへ移動する。
struct PageListPanelView: View {
    let viewModel: ReaderViewModel

    var body: some View {
        if let provider = viewModel.provider {
            let current = Set(viewModel.currentSpread?.pages ?? [])
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(provider.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(provider.pageCount)")
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 8)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(provider.pages) { page in
                                PanelListRow(
                                    title: viewModel.entryPath(of: page.index),
                                    subtitle: "\(page.index + 1)",
                                    isSelected: current.contains(page.index),
                                    action: { viewModel.go(to: page.index) }
                                ) {
                                    ThumbnailView(store: viewModel.pageThumbnails, key: page.index)
                                        .frame(width: 48, height: 48)
                                }
                                .id(page.index)
                            }
                        }
                    }
                    .onChange(of: viewModel.currentSpread?.first) { _, page in
                        if let page { proxy.scrollTo(page) }
                    }
                    .onAppear {
                        if let page = viewModel.currentSpread?.first { proxy.scrollTo(page, anchor: .center) }
                    }
                }
            }
        } else {
            Text("本を開いていません")
                .font(.system(size: 12))
                .foregroundStyle(Theme.grayText)
                .padding(8)
        }
    }
}
