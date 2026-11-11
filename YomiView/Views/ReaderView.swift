import SwiftUI

/// メインの表示領域。
struct ReaderView: View {
    @State private var viewModel = ReaderViewModel()
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black
            if viewModel.isBookOpen {
                PageImageView(state: viewModel.pageState)
            } else {
                emptyBookView
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .navigationTitle(viewModel.windowTitle)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.rightArrow) {
            viewModel.goNext()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            viewModel.goPrevious()
            return .handled
        }
        .focusedSceneValue(\.readerViewModel, viewModel)
        .alert(
            "本を開けません",
            isPresented: Binding(
                get: { viewModel.openError != nil },
                set: { if !$0 { viewModel.openError = nil } }
            ),
            presenting: viewModel.openError
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    private var emptyBookView: some View {
        VStack(spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 40))
            Text("フォルダ、ZIP、CBZ を開いてください")
            Button("開く…") { viewModel.presentOpenPanel() }
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - メニューから現在のウィンドウの ViewModel を参照する

struct ReaderViewModelKey: FocusedValueKey {
    typealias Value = ReaderViewModel
}

extension FocusedValues {
    var readerViewModel: ReaderViewModel? {
        get { self[ReaderViewModelKey.self] }
        set { self[ReaderViewModelKey.self] = newValue }
    }
}
