import SwiftUI

/// サムネイル1枚。画面に出たときに要求し、消えたら要求を取り消す。読み込み前は灰色の枠（NeeView の Thumbnail.Background）。
struct ThumbnailView<Key: Hashable & Sendable>: View {
    let store: ThumbnailStore<Key>
    let key: Key
    var placeholderSymbol = "photo"

    var body: some View {
        ZStack {
            if let image = store.image(for: key) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Theme.thumbnailBackground)
                    .overlay {
                        Image(systemName: store.hasFailed(key) ? "exclamationmark.triangle" : placeholderSymbol)
                            .foregroundStyle(Theme.thumbnailForeground)
                    }
            }
        }
        .onAppear { store.request(key) }
        .onDisappear { store.cancel(key) }
    }
}
