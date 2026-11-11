import SwiftUI

/// ウィンドウ全体。NeeView の画面構成（NeeView/MainWindow/MainWindow.xaml）に合わせ、
/// 上にアドレスバー、左右にサイドパネル、中央に本、下にページスライダーを置く。
struct ReaderView: View {
    @State private var viewModel: ReaderViewModel
    @FocusState private var isFocused: Bool
    @Environment(\.displayScale) private var displayScale
    @State private var isDropTargeted = false
    private let panelLayout: SidePanelLayout
    private var recentBooks: RecentBooksStore { viewModel.recentBooks }

    init(viewModel: ReaderViewModel? = nil, panelLayout: SidePanelLayout? = nil) {
        _viewModel = State(initialValue: viewModel ?? ReaderViewModel())
        self.panelLayout = panelLayout ?? .shared
    }

    var body: some View {
        VStack(spacing: 0) {
            AddressBarView(viewModel: viewModel) { isFocused = true }
            HStack(spacing: 0) {
                SideBarView(side: .left, layout: panelLayout)
                sidePanel(on: .left)
                mainView
                sidePanel(on: .right)
                SideBarView(side: .right, layout: panelLayout)
            }
            if viewModel.settings.isFilmStripVisible, viewModel.isBookOpen {
                FilmStripView(viewModel: viewModel)
                    .background {
                        // フィルムストリップの上のホイールはページ送り（NeeView の既定 MoveSelection）
                        ScrollWheelMonitor(isEnabled: true) { action in
                            switch action {
                            case .next: viewModel.goNext()
                            case .previous: viewModel.goPrevious()
                            }
                        }
                    }
            }
            PageSliderView(
                pageCount: viewModel.pageCount,
                currentPage: viewModel.currentSpread?.first ?? 0,
                isReversed: viewModel.readingDirection == .rightToLeft
            ) { page in
                viewModel.go(to: page)
            }
        }
        .background(Theme.windowBackground)
        .preferredColorScheme(.dark)
        .frame(minWidth: 500, minHeight: 360)
        .navigationTitle(viewModel.windowTitle)
        .focusedSceneValue(\.readerViewModel, viewModel)
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.openDropped(urls)
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                Rectangle()
                    .strokeBorder(Theme.accent, lineWidth: 4)
                    .allowsHitTesting(false)
            }
        }
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

    // MARK: - サイドパネル

    @ViewBuilder
    private func sidePanel(on side: SidePanelKind.Side) -> some View {
        if let panel = panelLayout.selected(on: side) {
            SidePanelContainer(
                title: panel.title,
                width: side == .left ? Bindable(panelLayout).leftWidth : Bindable(panelLayout).rightWidth,
                side: side
            ) {
                panelContent(panel)
            }
        }
    }

    @ViewBuilder
    private func panelContent(_ panel: SidePanelKind) -> some View {
        switch panel {
        case .bookshelf:
            BookshelfPanelView(bookshelf: viewModel.bookshelf, viewModel: viewModel)
        case .pageList:
            PageListPanelView(viewModel: viewModel)
        case .history:
            HistoryPanelView(recentBooks: recentBooks, viewModel: viewModel)
        }
    }

    // MARK: - 本の表示領域

    private var mainView: some View {
        ZStack {
            Theme.windowBackground
            if viewModel.isBookOpen {
                SpreadView(
                    pages: viewModel.displayedPages.map { ($0, viewModel.state(of: $0)) },
                    zoomMode: viewModel.zoomMode
                )
            } else {
                emptyBookView
            }
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.infoMessage {
                Text(message.text)
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Theme.notificationBackground)
                    .padding(.bottom, 40)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.infoMessage)
        .clipped()
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
        .background {
            ScrollWheelMonitor(isEnabled: viewModel.isBookOpen && viewModel.zoomMode == .fit) { action in
                switch action {
                case .next: viewModel.goNext()
                case .previous: viewModel.goPrevious()
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onChange(of: viewModel.currentSpread) { viewModel.scheduleLoads() }
        .onChange(of: viewModel.bookURL) { isFocused = true }
        .onKeyPress(keys: Self.handledKeys, phases: [.down, .repeat]) { press in
            handleKey(press)
        }
    }

    // MARK: - キーボード操作（計画書 5.4 と追加仕様の ↑↓）

    private static let handledKeys: Set<KeyEquivalent> = [
        .leftArrow, .rightArrow, .upArrow, .downArrow, .space, .home, .end,
        "f", "F", "m", "M", "d", "D", "b", "B", "h", "H",
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
            default:
                guard let panel = SidePanelKind.allCases.first(where: {
                    $0.toggleKey.map(String.init) == press.characters.lowercased()
                }) else { return .ignored }
                panelLayout.toggle(panel)
            }
        }
        return .handled
    }

    private var emptyBookView: some View {
        VStack(spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 40))
            Text("フォルダ、ZIP、CBZ、PDF を開くか、ここにドロップしてください")
            Button("開く…") { viewModel.presentOpenPanel() }
        }
        .foregroundStyle(Theme.grayText)
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
