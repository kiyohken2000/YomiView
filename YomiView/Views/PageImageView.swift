import SwiftUI

/// ページ1枚。与えられた枠いっぱいに表示する（縦横比は呼び出し側で合わせる）。
struct PageImageView: View {
    let state: ReaderViewModel.PageState

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let image):
            Image(decorative: image.cgImage, scale: 1)
                .resizable()
                .interpolation(.high)
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text("読み込めません")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
