import SwiftUI

/// ページ1枚を、ウィンドウに合わせて表示する。
struct PageImageView: View {
    let state: ReaderViewModel.PageState

    var body: some View {
        switch state {
        case .empty:
            EmptyView()
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .loaded(let image):
            Image(decorative: image.cgImage, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text("読み込めません")
                    .font(.headline)
                Text(message)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }
}
