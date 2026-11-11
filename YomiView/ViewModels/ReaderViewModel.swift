import AppKit
import Foundation
import Observation

/// 表示中の本・ページ・表示モードの状態。View はこの状態を表示するだけにする。
@MainActor
@Observable
final class ReaderViewModel {
    /// ページ1枚の表示状態
    enum PageState: Equatable {
        case loading
        case loaded(PageImage)
        case failed(String)

        static func == (lhs: PageState, rhs: PageState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case let (.loaded(a), .loaded(b)): return a.cgImage === b.cgImage
            case let (.failed(a), .failed(b)): return a == b
            default: return false
            }
        }
    }

    /// 画像の大きさ
    enum ZoomMode {
        /// ウィンドウに合わせる
        case fit
        /// 原寸
        case original
    }

    let settings: AppSettings
    let recentBooks: RecentBooksStore

    private(set) var provider: PageProvider?
    /// 開いている本の場所（読書位置の保存に使う）
    private(set) var bookURL: URL?
    /// 現在のページ（表示中の組に含まれるページ）
    private(set) var currentIndex: Int = 0 {
        didSet { if currentIndex != oldValue { savePosition() } }
    }
    /// 読み込みに失敗したページとその理由
    private(set) var failedPages: [Int: String] = [:]
    /// キャッシュの中身が変わるたびに増える（View の更新用）
    private(set) var cacheRevision = 0
    /// 読み込んで分かった、各ページが横長かどうか
    private(set) var widePages: [Int: Bool] = [:]
    /// M キーなどで手動で選んだ表示モード。nil なら表示領域の形で自動的に決める
    var manualViewMode: ViewMode? {
        didSet { if manualViewMode != oldValue { savePosition() } }
    }
    /// 画像の大きさ（初期値はウィンドウに合わせる）
    var zoomMode: ZoomMode = .fit {
        didSet { if zoomMode != oldValue { scheduleLoads() } }
    }
    /// 表示領域の大きさ（ポイント）
    private(set) var containerSize: CGSize = .zero
    /// 表示領域の画面の倍率（Retina なら 2）
    private(set) var displayScale: CGFloat = 2
    /// 本を開けなかったときのエラー（アラート表示用）
    var openError: String?

    /// キャッシュする件数の上限
    static let cacheCapacity = 8
    /// 現在の組の前後に先読みするページ数
    static let prefetchCount = 2

    @ObservationIgnored let cache = ImageCache(capacity: cacheCapacity)
    @ObservationIgnored private var loadQueue: [Int] = []
    @ObservationIgnored private var loaderTask: Task<Void, Never>?

    init(settings: AppSettings? = nil, recentBooks: RecentBooksStore? = nil) {
        self.settings = settings ?? .shared
        self.recentBooks = recentBooks ?? .shared
    }

    var isBookOpen: Bool { provider != nil }
    var pageCount: Int { provider?.pageCount ?? 0 }

    // MARK: - 表示モードと見開き

    /// 表示モード。手動の指定がなければ、表示領域が横長なら見開き。
    var viewMode: ViewMode {
        manualViewMode ?? (containerSize.width > containerSize.height ? .spread : .single)
    }

    var readingDirection: ReadingDirection { settings.readingDirection }

    var spreads: [Spread] {
        SpreadCalculator.spreads(
            pageCount: pageCount,
            mode: viewMode,
            options: settings.spreadOptions,
            isWide: { [widePages] in widePages[$0] ?? false }
        )
    }

    var currentSpread: Spread? {
        let spreads = spreads
        return SpreadCalculator.spreadIndex(containing: currentIndex, in: spreads).map { spreads[$0] }
    }

    /// 画面に左から並べるページ
    var displayedPages: [Int] {
        guard let currentSpread else { return [] }
        return SpreadCalculator.displayOrder(of: currentSpread, direction: readingDirection)
    }

    func state(of page: Int) -> PageState {
        _ = cacheRevision
        if let message = failedPages[page] { return .failed(message) }
        // 大きさが足りなくても、読み直しが終わるまでは手元の画像を表示する
        if let image = cache.image(for: page) { return .loaded(image) }
        return .loading
    }

    /// ウィンドウタイトル（本の名前と現在ページ）
    var windowTitle: String {
        guard let provider, let spread = currentSpread else { return "YomiView" }
        let pages = spread.pages.count > 1 ? "\(spread.first + 1)-\(spread.last + 1)" : "\(spread.first + 1)"
        return "\(provider.title) (\(pages) / \(provider.pageCount))"
    }

    func updateContainerSize(_ size: CGSize, displayScale: CGFloat? = nil) {
        let scale = displayScale ?? self.displayScale
        guard size != containerSize || scale != self.displayScale else { return }
        containerSize = size
        self.displayScale = scale
        scheduleLoads()
    }

    /// 見開き / 1ページを切り替える（以後は自動切り替えより優先）
    func toggleViewMode() {
        manualViewMode = viewMode.toggled
        scheduleLoads()
    }

    /// 左開き / 右開きを切り替える
    func toggleReadingDirection() {
        settings.readingDirection = settings.readingDirection.toggled
    }

    // MARK: - 本を開く

    /// ファイル選択ダイアログを表示して本を開く。
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "本を開く"
        panel.prompt = "開く"
        panel.message = "フォルダ、ZIP、CBZ、PDF を選択してください"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = BookSource.openPanelContentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    /// ドロップされたファイルを開く。複数の場合は最初の1つだけを開く。
    @discardableResult
    func openDropped(_ urls: [URL]) -> Bool {
        guard let url = urls.first(where: \.isFileURL) else {
            openError = "ドロップされた項目を本として開けません。フォルダ、ZIP、CBZ、PDF をドロップしてください。"
            return false
        }
        open(url)
        return true
    }

    /// 本を開く。前に読んだことのある本なら、最後に読んだページと見開き設定を復元する。
    func open(_ url: URL) {
        do {
            let provider = try BookSource.detect(url).makeProvider()
            let saved = recentBooks.recordOpen(url)
            bookURL = nil
            manualViewMode = saved.viewMode
            setProvider(provider, startIndex: saved.lastPage)
            bookURL = url
            savePosition()
        } catch {
            openError = error.localizedDescription
        }
    }

    private func savePosition() {
        guard let bookURL else { return }
        recentBooks.updatePosition(of: bookURL, page: currentIndex, viewMode: manualViewMode)
    }

    /// 開いた本を設定し、指定ページ（既定は先頭）を表示する。
    func setProvider(_ provider: PageProvider, startIndex: Int = 0) {
        bookURL = nil
        loaderTask?.cancel()
        loaderTask = nil
        loadQueue = []
        cache.removeAll()
        cacheRevision += 1
        failedPages = [:]
        widePages = [:]
        self.provider = provider
        currentIndex = min(max(0, startIndex), max(0, provider.pageCount - 1))
        scheduleLoads()
    }

    // MARK: - ページ送り

    /// 次のページ（見開きでは次の組）へ。末尾では何もしない。
    func goNext() {
        moveSpread(by: 1)
    }

    /// 前のページ（見開きでは前の組）へ。先頭では何もしない。
    func goPrevious() {
        moveSpread(by: -1)
    }

    /// 画面の左側のページへ（右開きでは次、左開きでは前）
    func goLeft() {
        readingDirection == .rightToLeft ? goNext() : goPrevious()
    }

    /// 画面の右側のページへ（右開きでは前、左開きでは次）
    func goRight() {
        readingDirection == .rightToLeft ? goPrevious() : goNext()
    }

    /// 先頭の組へ
    func goFirst() {
        guard let first = spreads.first, first.first != currentIndex else { return }
        currentIndex = first.first
        scheduleLoads()
    }

    /// 末尾の組へ
    func goLast() {
        guard let last = spreads.last, currentSpread != last else { return }
        currentIndex = last.first
        scheduleLoads()
    }

    private func moveSpread(by offset: Int) {
        let spreads = spreads
        guard let index = SpreadCalculator.spreadIndex(containing: currentIndex, in: spreads) else { return }
        let target = index + offset
        guard spreads.indices.contains(target) else { return }
        currentIndex = spreads[target].first
        scheduleLoads()
    }

    // MARK: - 画像の読み込み

    /// 読み込む画像の長辺（ピクセル）。表示領域の長辺に画面の倍率を掛け、256 単位に切り上げる。
    /// 少しのウィンドウサイズ変更で読み直さないようにするため。
    var requiredPixelSize: Int {
        if zoomMode == .original { return Self.originalMaxPixelSize }
        let longSide = max(containerSize.width, containerSize.height) * displayScale
        guard longSide > 0 else { return Self.screenMaxPixelSize() }
        return max(256, Int((longSide / 256).rounded(.up)) * 256)
    }

    /// 原寸表示で読み込む長辺の上限（ピクセル）。これより大きい画像は縮小する
    static let originalMaxPixelSize = 8192

    /// 表示領域の大きさが分からないときに使う、画面の長辺（ピクセル）
    nonisolated static func screenMaxPixelSize() -> Int {
        let sizes = NSScreen.screens.map { screen in
            max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor
        }
        return Int(sizes.max() ?? 2048)
    }

    /// 読み込むページを優先順に返す：表示中のページ、次のページ、前のページ。
    var pagesToLoad: [Int] {
        guard let currentSpread else { return [] }
        let after = (1...Self.prefetchCount).map { currentSpread.last + $0 }
        let before = (1...Self.prefetchCount).map { currentSpread.first - $0 }
        return (currentSpread.pages + after + before).filter { (0..<pageCount).contains($0) }
    }

    /// 表示中と前後のページの読み込みを予約する。表示に関わる状態が変わるたびに呼ぶ。
    func scheduleLoads() {
        let size = requiredPixelSize
        loadQueue = pagesToLoad.filter { failedPages[$0] == nil && !cache.contains($0, sufficientFor: size) }
        if loaderTask == nil, !loadQueue.isEmpty {
            loaderTask = Task { [weak self] in await self?.runLoader() }
        }
    }

    /// 予約されたページを1枚ずつバックグラウンドで読み込む。表示はブロックしない。
    private func runLoader() async {
        defer { loaderTask = nil }
        while !Task.isCancelled, !loadQueue.isEmpty, let provider {
            let index = loadQueue.removeFirst()
            let maxPixelSize = requiredPixelSize
            guard failedPages[index] == nil, !cache.contains(index, sufficientFor: maxPixelSize) else { continue }
            let result: Result<PageImage, Error> = await Task.detached(priority: .userInitiated) {
                Result { try provider.loadImage(at: index, maxPixelSize: maxPixelSize) }
            }.value
            // 読み込み中に別の本を開いた場合は捨てる
            guard !Task.isCancelled, self.provider === provider else { return }
            switch result {
            case .success(let image):
                cache.insert(image, for: index, maxPixelSize: maxPixelSize)
                cacheRevision += 1
                if widePages[index] != image.isWide {
                    widePages[index] = image.isWide
                    // 横長と分かったことで組み合わせが変わる場合がある
                    scheduleLoads()
                }
            case .failure(let error):
                failedPages[index] = error.localizedDescription
            }
        }
    }
}
