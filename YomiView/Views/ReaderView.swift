import SwiftUI

/// ウィンドウ全体。NeeView の画面構成（NeeView/MainWindow/MainWindow.xaml）に合わせ、
/// 上にアドレスバー、左右にサイドパネル、中央に本、下にページスライダーを置く。
struct ReaderView: View {
    @State private var viewModel: ReaderViewModel
    @FocusState private var isFocused: Bool
    @Environment(\.displayScale) private var displayScale
    @State private var isDropTargeted = false
    @State private var dragState: DragState?
    @State private var longPressTask: Task<Void, Never>?
    @State private var cursorHideTask: Task<Void, Never>?
    @State private var loupeAnchor: UnitPoint = .center
    @State private var hoverLocation: CGPoint = .zero
    @State private var magnifyBase: CGFloat?
    @State private var isFullScreen = false
    @State private var autoHide = AutoHideState()
    @State private var autoHideTasks: [AutoHideState.Edge: Task<Void, Never>] = [:]
    private let panelLayout: SidePanelLayout
    private var recentBooks: RecentBooksStore { viewModel.recentBooks }

    /// - Parameter isFullScreen: フルスクリーンとして表示を始める（スナップショット用）
    init(viewModel: ReaderViewModel? = nil, panelLayout: SidePanelLayout? = nil, isFullScreen: Bool = false) {
        _viewModel = State(initialValue: viewModel ?? ReaderViewModel())
        _isFullScreen = State(initialValue: isFullScreen)
        self.panelLayout = panelLayout ?? .shared
    }

    var body: some View {
        layout
        .background(Theme.windowBackground)
        .background { FullScreenObserver { isFullScreen = $0 } }
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

    // MARK: - 画面構成

    /// フルスクリーンで自動非表示にするか
    private var isAutoHiding: Bool {
        isFullScreen && viewModel.settings.isAutoHideInFullScreen
    }

    @ViewBuilder
    private var layout: some View {
        if isAutoHiding {
            autoHideLayout
        } else {
            VStack(spacing: 0) {
                addressBar
                HStack(spacing: 0) {
                    leftPanels
                    mainView
                    rightPanels
                }
                bottomBars
            }
        }
    }

    private var addressBar: some View {
        AddressBarView(viewModel: viewModel) { isFocused = true }
    }

    private var leftPanels: some View {
        HStack(spacing: 0) {
            SideBarView(side: .left, layout: panelLayout)
            sidePanel(on: .left)
        }
    }

    private var rightPanels: some View {
        HStack(spacing: 0) {
            sidePanel(on: .right)
            SideBarView(side: .right, layout: panelLayout)
        }
    }

    private var bottomBars: some View {
        VStack(spacing: 0) {
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
    }

    /// フルスクリーンの自動非表示：本を画面いっぱいに表示し、端にマウスを近づけたときだけ
    /// アドレスバー・サイドパネル・フィルムストリップ・ページスライダーを本の上に重ねて表示する（NeeView の AutoHide）。
    private var autoHideLayout: some View {
        GeometryReader { geometry in
            autoHideContent
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): updateAutoHide(at: location, in: geometry.size)
                    case .ended: updateAutoHide(at: nil, in: geometry.size)
                    }
                }
        }
        .onDisappear {
            autoHideTasks.values.forEach { $0.cancel() }
            autoHideTasks = [:]
            autoHide.visible = []
        }
    }

    private var autoHideContent: some View {
        ZStack {
            mainView
            HStack(spacing: 0) {
                if autoHide.visible.contains(.left) {
                    leftPanels
                        .measureDepth(\.width) { autoHide.depths[.left] = $0 }
                        .transition(.move(edge: .leading))
                }
                Spacer(minLength: 0)
                if autoHide.visible.contains(.right) {
                    rightPanels
                        .measureDepth(\.width) { autoHide.depths[.right] = $0 }
                        .transition(.move(edge: .trailing))
                }
            }
            VStack(spacing: 0) {
                if autoHide.visible.contains(.top) {
                    addressBar
                        .measureDepth(\.height) { autoHide.depths[.top] = $0 }
                        .transition(.move(edge: .top))
                }
                Spacer(minLength: 0)
                if autoHide.visible.contains(.bottom) {
                    bottomBars
                        .measureDepth(\.height) { autoHide.depths[.bottom] = $0 }
                        .transition(.move(edge: .bottom))
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: autoHide.visible)
    }

    /// マウスの位置に合わせて端の表示を変える。表示はすぐに、隠すのは少し待ってから。
    private func updateAutoHide(at location: CGPoint?, in size: CGSize) {
        let wanted = autoHide.edges(at: location, in: size)
        for edge in AutoHideState.Edge.allCases {
            if wanted.contains(edge) {
                autoHideTasks[edge]?.cancel()
                autoHideTasks[edge] = nil
                if !autoHide.visible.contains(edge) { autoHide.visible.insert(edge) }
            } else if autoHide.visible.contains(edge), autoHideTasks[edge] == nil {
                autoHideTasks[edge] = Task {
                    try? await Task.sleep(nanoseconds: AutoHideState.hideDelay)
                    guard !Task.isCancelled else { return }
                    autoHide.visible.remove(edge)
                    autoHideTasks[edge] = nil
                }
            }
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
        case .fileInfo:
            FileInfoPanelView(viewModel: viewModel)
        case .navigator:
            NavigatorPanelView(viewModel: viewModel)
        case .bookmark:
            BookmarkPanelView(bookmarks: BookmarkStore.shared, viewModel: viewModel)
        }
    }

    // MARK: - 本の表示領域

    private var mainView: some View {
        ZStack {
            if viewModel.isBookOpen {
                // ページは拡大前の大きさで並べるため、表示領域の大きさに影響しないよう overlay に置く
                CanvasBackground(type: viewModel.settings.background, autoColor: viewModel.autoBackgroundColor)
                    .overlay {
                        SpreadView(
                            canvas: viewModel.canvas,
                            transform: viewModel.transform,
                            state: { viewModel.state(of: $0) },
                            loupeScale: viewModel.isLoupeActive ? viewModel.loupeScale : nil,
                            loupeAnchor: loupeAnchor
                        )
                    }
            } else {
                Theme.windowBackground
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
            ScrollWheelMonitor(isEnabled: viewModel.isBookOpen) { action in
                viewModel.resetSlideShowTimer()
                viewModel.scroll(action)
            }
        }
        .contentShape(Rectangle())
        .gesture(pointerGesture)
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let base = magnifyBase ?? viewModel.transform.scale
                    magnifyBase = base
                    viewModel.setUserScale(base * value.magnification)
                }
                .onEnded { _ in magnifyBase = nil }
        )
        .onContinuousHover { phase in
            if case .active(let location) = phase {
                hoverLocation = location
                scheduleCursorHide()
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onChange(of: viewModel.currentSpread) { viewModel.scheduleLoads() }
        // 設定画面で変えた並び順・サブフォルダーの読み込みを、開いている本に反映する
        .onChange(of: viewModel.settings.pageSortMode) { viewModel.applyPageSort() }
        .onChange(of: viewModel.settings.isRecursiveFolder) { viewModel.applyRecursiveFolder() }
        .onChange(of: viewModel.bookURL) { isFocused = true }
        .onKeyPress(keys: Self.handledKeys, phases: [.down, .repeat]) { press in
            handleKey(press)
        }
    }

    // MARK: - マウス操作（NeeView の既定：ドラッグで移動、長押しでルーペ、カーソルを自動で隠す）

    /// ドラッグとみなす最小の移動量（NeeView の MinimumDragDistance）
    private static let minimumDragDistance: CGFloat = 5
    /// 長押しでルーペになるまでの時間（NeeView の LongButtonDownTime）
    private static let longPressDuration: UInt64 = 1_000_000_000
    /// カーソルを隠すまでの時間（NeeView の CursorHideTime）
    private static let cursorHideDelay: UInt64 = 2_000_000_000

    private var pointerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if dragState == nil {
                    dragState = DragState(lastTranslation: .zero)
                    loupeAnchor = anchor(for: value.startLocation)
                    longPressTask?.cancel()
                    longPressTask = Task {
                        try? await Task.sleep(nanoseconds: Self.longPressDuration)
                        guard !Task.isCancelled, dragState?.isDragging == false else { return }
                        viewModel.isLoupeActive = true
                    }
                }
                guard var state = dragState else { return }
                if viewModel.isLoupeActive {
                    loupeAnchor = anchor(for: value.location)
                    return
                }
                let distance = hypot(value.translation.width, value.translation.height)
                if !state.isDragging, distance >= Self.minimumDragDistance {
                    state.isDragging = true
                    longPressTask?.cancel()
                }
                if state.isDragging {
                    viewModel.pan(by: CGSize(
                        width: value.translation.width - state.lastTranslation.width,
                        height: value.translation.height - state.lastTranslation.height
                    ))
                    state.lastTranslation = value.translation
                }
                dragState = state
            }
            .onEnded { _ in
                viewModel.resetSlideShowTimer()
                longPressTask?.cancel()
                viewModel.isLoupeActive = false
                dragState = nil
                isFocused = true
            }
    }

    private struct DragState {
        var lastTranslation: CGSize
        var isDragging = false
    }

    private func anchor(for location: CGPoint) -> UnitPoint {
        let size = viewModel.containerSize
        guard size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: min(1, max(0, location.x / size.width)), y: min(1, max(0, location.y / size.height)))
    }

    /// マウスを動かさずに2秒たったらカーソルを隠す（次に動かすと表示される）
    private func scheduleCursorHide() {
        cursorHideTask?.cancel()
        cursorHideTask = Task {
            try? await Task.sleep(nanoseconds: Self.cursorHideDelay)
            guard !Task.isCancelled, viewModel.isBookOpen else { return }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    // MARK: - キーボード操作（計画書 5.4 と追加仕様の ↑↓）

    private static let handledKeys: Set<KeyEquivalent> = [
        .leftArrow, .rightArrow, .upArrow, .downArrow, .space, .home, .end,
        "f", "F", "m", "M", "d", "D", "b", "B", "h", "H", "p", "P", "i", "I", "n", "N",
    ]

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // ⌘・⌃・⌥ 付きはメニューのショートカットなどに任せる
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        viewModel.resetSlideShowTimer()
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

private extension View {
    /// 端からの奥行き（幅または高さ）を測って知らせる
    func measureDepth(_ keyPath: KeyPath<CGSize, CGFloat>, _ action: @escaping (CGFloat) -> Void) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { action(geometry.size[keyPath: keyPath]) }
                    .onChange(of: geometry.size[keyPath: keyPath]) { _, value in action(value) }
            }
        }
    }
}
