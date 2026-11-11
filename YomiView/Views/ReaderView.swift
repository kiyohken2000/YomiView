import SwiftUI

/// メインの表示領域。
struct ReaderView: View {
    @State private var viewModel = ReaderViewModel()
    @FocusState private var isFocused: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            Color.black
            if viewModel.isBookOpen {
                SpreadView(
                    pages: viewModel.displayedPages.map { ($0, viewModel.state(of: $0)) },
                    zoomMode: viewModel.zoomMode
                )
            } else {
                emptyBookView
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { viewModel.updateContainerSize(geometry.size, displayScale: displayScale) }
                    .onChange(of: geometry.size) { _, size in
                        viewModel.updateContainerSize(size, displayScale: displayScale)
                    }
                    .onChange(of: displayScale) { _, scale in
                        viewModel.updateContainerSize(geometry.size, displayScale: scale)
                    }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .navigationTitle(viewModel.windowTitle)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onChange(of: viewModel.currentSpread) { viewModel.scheduleLoads() }
        .onKeyPress(keys: Self.handledKeys, phases: [.down, .repeat]) { press in
            handleKey(press)
        }
        .background {
            ScrollWheelMonitor(isEnabled: viewModel.isBookOpen && viewModel.zoomMode == .fit) { action in
                switch action {
                case .next: viewModel.goNext()
                case .previous: viewModel.goPrevious()
                }
            }
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

    // MARK: - キーボード操作（計画書 5.4 と追加仕様の ↑↓）

    private static let handledKeys: Set<KeyEquivalent> = [
        .leftArrow, .rightArrow, .upArrow, .downArrow, .space, .home, .end,
        "f", "F", "m", "M", "d", "D",
    ]

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // ⌘・⌃・⌥ 付きはメニューのショートカットなどに任せる
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        let isRepeat = press.phase == .repeat
        switch press.key {
        case .rightArrow: viewModel.goRight()
        case .leftArrow: viewModel.goLeft()
        case .downArrow: viewModel.goNext()
        case .upArrow: viewModel.goPrevious()
        case .space:
            press.modifiers.contains(.shift) ? viewModel.goPrevious() : viewModel.goNext()
        case .home: viewModel.goFirst()
        case .end: viewModel.goLast()
        default:
            // 切り替え操作はキーを押し続けても繰り返さない
            guard !isRepeat else { return .handled }
            switch press.characters.lowercased() {
            case "f": NSApp.keyWindow?.toggleFullScreen(nil)
            case "m": viewModel.toggleViewMode()
            case "d": viewModel.toggleReadingDirection()
            default: return .ignored
            }
        }
        return .handled
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
