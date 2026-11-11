import SwiftUI

/// メインの表示領域。
struct ReaderView: View {
    @State private var viewModel = ReaderViewModel()
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black
            if viewModel.isBookOpen {
                SpreadView(pages: viewModel.displayedPages.map { ($0, viewModel.state(of: $0)) })
            } else {
                emptyBookView
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { viewModel.updateContainerSize(geometry.size) }
                    .onChange(of: geometry.size) { _, size in viewModel.updateContainerSize(size) }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .navigationTitle(viewModel.windowTitle)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onChange(of: viewModel.currentSpread) { viewModel.scheduleLoads() }
        .onKeyPress(.rightArrow) {
            viewModel.goRight()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            viewModel.goLeft()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "mMdD")) { press in
            guard press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
            switch press.characters.lowercased() {
            case "m": viewModel.toggleViewMode()
            case "d": viewModel.toggleReadingDirection()
            default: return .ignored
            }
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
            Text("フォルダ、ZIP、CBZ、PDF を開いてください")
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
