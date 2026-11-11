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

    /// 表示中のページの並べ方と大きさ（CanvasLayout で計算した結果）
    struct Canvas: Equatable {
        struct Page: Equatable {
            let index: Int
            /// 高さを揃えたときの大きさ（拡大率を掛ける前）
            let size: CGSize
            /// 横長ページを分割して表示するとき、画像のどちらの半分を表示するか
            var half: PageHalf?
        }

        /// 左から並べるページ
        var pages: [Page] = []
        /// ページを並べた全体の大きさ（拡大率を掛ける前）
        var frame: CGSize = .zero
        /// ストレッチの倍率
        var stretchScale: CGFloat = 1
        /// ストレッチ × ユーザーの拡大率
        var scale: CGFloat = 1
        /// 回転・拡大後に外接する大きさ
        var content: CGSize = .zero
        /// 表示領域の中央からの移動量
        var offset: CGSize = .zero
    }

    /// 本を開けなかったときの知らせ方
    enum FailureStyle {
        /// アラートで知らせる（ファイル選択・ドロップ・アドレス入力など、明示的に開いたとき）
        case alert
        /// 画面下の通知で知らせる（本棚や前後の本への移動など、続けて操作するとき）
        case notice
    }

    /// 画面に一時的に表示する通知（NeeView の InfoMessage）
    struct InfoMessage: Equatable {
        let id = UUID()
        let text: String
    }

    let settings: AppSettings
    let recentBooks: RecentBooksStore
    let bookshelf: BookshelfModel

    private(set) var provider: PageProvider?
    /// 並べ替える前の PageProvider（並び順を変えたときに使う）
    @ObservationIgnored private var baseProvider: PageProvider?
    /// 開いている本に適用している並び順
    private(set) var appliedSortMode: PageSortMode = .fileName
    /// 開いている本の場所（読書位置の保存に使う）
    private(set) var bookURL: URL?
    /// 現在のページ（表示中の組に含まれるページ）
    private(set) var currentIndex: Int = 0 {
        didSet {
            guard currentIndex != oldValue else { return }
            savePosition()
            resetTransformForNewPage()
        }
    }
    /// 横長ページを分割して表示しているとき、表示中の半分（NeeView の PagePosition.Part）
    private(set) var currentPart: PagePart? {
        didSet { if currentPart != oldValue { resetTransformForNewPage() } }
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
    /// 拡大・回転・反転・移動の状態
    var transform = ViewTransform() {
        didSet { if transform.scale != oldValue.scale { scheduleLoads() } }
    }
    /// ルーペ（NeeView の既定どおり、左ボタンを長押ししている間だけ有効）
    var isLoupeActive = false {
        didSet { if isLoupeActive != oldValue { scheduleLoads() } }
    }
    /// ルーペの倍率（NeeView の既定 2、1〜10、ホイールで 1 ずつ変える）
    private(set) var loupeScale: CGFloat = 2
    /// 読み込んで分かったページの大きさ（原寸表示のポイント）
    private(set) var pageSizes: [Int: CGSize] = [:]
    /// 読み込んで分かったページの縁の色（背景「画像に合わせた色」用）
    private(set) var pageEdgeColors: [Int: CGColor] = [:]
    @ObservationIgnored private var pendingOrigin: ViewOrigin?
    /// 表示領域の大きさ（ポイント）
    private(set) var containerSize: CGSize = .zero
    /// 表示領域の画面の倍率（Retina なら 2）
    private(set) var displayScale: CGFloat = 2
    /// 本を開けなかったときのエラー（アラート表示用）
    var openError: String?
    /// 一時的な通知
    private(set) var infoMessage: InfoMessage?
    /// 開いた本の履歴（戻る / 進む用。NeeView の PrevBookHistory / NextBookHistory）
    @ObservationIgnored private var bookHistory: [URL] = []
    /// スライドショーを再生中か（NeeView の ToggleSlideShow）
    private(set) var isSlideShowPlaying = false
    @ObservationIgnored private var slideShowTask: Task<Void, Never>?
    /// スライドショーのページ送り中（ユーザーの操作と区別してタイマーをリセットしないため）
    @ObservationIgnored private var isSlideShowAdvancing = false
    private(set) var bookHistoryIndex = -1

    /// キャッシュする件数の上限
    static let cacheCapacity = 8
    /// 現在の組の前後に先読みするページ数
    static let prefetchCount = 2

    @ObservationIgnored let cache = ImageCache(capacity: cacheCapacity)
    /// ページのサムネイル（フィルムストリップとページリスト用）
    @ObservationIgnored let pageThumbnails = ThumbnailStore<Int>(capacity: 100) { _ in
        throw BookError.pageOutOfRange(0)
    }
    @ObservationIgnored private var loadQueue: [Int] = []
    @ObservationIgnored private var loaderTask: Task<Void, Never>?

    init(settings: AppSettings? = nil, recentBooks: RecentBooksStore? = nil, bookshelf: BookshelfModel? = nil) {
        self.settings = settings ?? .shared
        self.recentBooks = recentBooks ?? .shared
        self.bookshelf = bookshelf ?? BookshelfModel()
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
        return SpreadCalculator.spreadIndex(containing: currentIndex, part: currentPart, in: spreads).map { spreads[$0] }
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
    ///
    /// NeeView の既定の書式に合わせる：1ページは `本 (ページ / 総数) - ページ名`、
    /// 2ページは `本 (ページ / 総数) - 左のページ名 | 右のページ名`。
    var windowTitle: String {
        guard let provider, let spread = currentSpread else { return "YomiView" }
        let names = displayedPages.map { entryPath(of: $0) }.joined(separator: " | ")
        return "\(provider.title) (\(spread.first + 1) / \(provider.pageCount)) - \(names)"
    }

    /// ページの場所の表示用文字列。アーカイブ内のフォルダは ` > ` でつなぐ（NeeView の {EntryPath:/ > }）
    func entryPath(of page: Int) -> String {
        guard let provider, provider.pages.indices.contains(page) else { return "" }
        let item = provider.pages[page]
        switch item.kind {
        case .archiveEntry(let path):
            return path.split(separator: "/").joined(separator: " > ")
        case .file:
            // サブフォルダーを読み込むときは、名前がフォルダからの相対パスになる
            return item.name.split(separator: "/").joined(separator: " > ")
        case .pdfPage:
            return item.name
        }
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
    /// 開いた本の親フォルダを本棚に表示し、本の履歴に記録する。
    func open(_ url: URL, failure: FailureStyle = .alert, recordHistory: Bool = true) {
        do {
            let provider = try BookSource.detect(url).makeProvider(recursiveFolder: settings.isRecursiveFolder)
            let saved = recentBooks.recordOpen(url)
            bookURL = nil
            manualViewMode = saved.viewMode
            setProvider(provider, startIndex: saved.lastPage)
            bookURL = url
            savePosition()
            bookshelf.reveal(url)
            if recordHistory { pushBookHistory(url) }
        } catch {
            switch failure {
            case .alert:
                openError = error.localizedDescription
            case .notice:
                // 開けなくても本棚の選択は移し、続けて前後の本へ移動できるようにする
                bookshelf.selected = url.standardizedFileURL
                showInfo(error.localizedDescription)
            }
        }
    }

    // MARK: - 前後の本・本の履歴

    /// 本棚で次の本を開く（NeeView の NextBook）
    func openNextBook() {
        openNeighborBook(offset: 1, failText: "次のブックはありません")
    }

    /// 本棚で前の本を開く（NeeView の PrevBook）
    func openPreviousBook() {
        openNeighborBook(offset: -1, failText: "前のブックはありません")
    }

    private func openNeighborBook(offset: Int, failText: String) {
        if bookshelf.selected == nil, let bookURL { bookshelf.reveal(bookURL) }
        guard let item = bookshelf.neighbor(offset: offset) else {
            showInfo(failText)
            return
        }
        open(item.url, failure: .notice)
    }

    /// 開いている本の親フォルダを本として開く（NeeView の MoveToParentBook）
    func openParentBook() {
        guard let bookURL, bookURL.path != "/" else { return }
        open(bookURL.deletingLastPathComponent(), failure: .notice)
    }

    var canGoBackBook: Bool { bookHistoryIndex > 0 }
    var canGoForwardBook: Bool { bookHistoryIndex >= 0 && bookHistoryIndex < bookHistory.count - 1 }

    /// 本の履歴を戻る
    func goBackBook() {
        guard canGoBackBook else { return }
        bookHistoryIndex -= 1
        open(bookHistory[bookHistoryIndex], failure: .notice, recordHistory: false)
    }

    /// 本の履歴を進む
    func goForwardBook() {
        guard canGoForwardBook else { return }
        bookHistoryIndex += 1
        open(bookHistory[bookHistoryIndex], failure: .notice, recordHistory: false)
    }

    private func pushBookHistory(_ url: URL) {
        let url = url.standardizedFileURL
        if bookHistoryIndex >= 0, bookHistory[bookHistoryIndex] == url { return }
        bookHistory.removeSubrange((bookHistoryIndex + 1)...)
        bookHistory.append(url)
        bookHistoryIndex = bookHistory.count - 1
    }

    /// 画面に通知を出し、2秒後に消す
    func showInfo(_ text: String) {
        let message = InfoMessage(text: text)
        infoMessage = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self?.infoMessage == message { self?.infoMessage = nil }
        }
    }

    private func savePosition() {
        guard let bookURL else { return }
        recentBooks.updatePosition(of: bookURL, page: currentIndex, viewMode: manualViewMode)
    }

    /// 開いた本を設定し、設定の並び順に並べ替えて、指定ページ（既定は先頭）を表示する。
    func setProvider(_ provider: PageProvider, startIndex: Int = 0) {
        baseProvider = provider
        let mode = settings.pageSortMode
        installProvider(Self.sorted(provider, mode: mode), sortMode: mode, startIndex: startIndex)
    }

    /// 並び順を変え、開いている本を並べ替える（シャッフルは選ぶたびに混ぜ直す）
    func setPageSortMode(_ mode: PageSortMode) {
        settings.pageSortMode = mode
        applyPageSort(force: true)
    }

    /// 設定の並び順を開いている本に適用する。表示中のページは並べ替えた後も表示し続ける。
    func applyPageSort(force: Bool = false) {
        guard let baseProvider, let provider else { return }
        let mode = settings.pageSortMode
        guard force || mode != appliedSortMode else { return }
        let current = provider.pages.indices.contains(currentIndex) ? provider.pages[currentIndex].kind : nil
        let sorted = Self.sorted(baseProvider, mode: mode)
        let start = sorted.pages.firstIndex { $0.kind == current } ?? 0
        let url = bookURL
        installProvider(sorted, sortMode: mode, startIndex: start)
        bookURL = url
        savePosition()
    }

    /// 「サブフォルダーを読み込む」を切り替え、フォルダの本を開いていれば読み込み直す
    func setRecursiveFolder(_ recursive: Bool) {
        settings.isRecursiveFolder = recursive
        applyRecursiveFolder()
    }

    /// 開いているフォルダの本に「サブフォルダーを読み込む」を反映する
    func applyRecursiveFolder() {
        guard let bookURL, let folder = baseProvider as? FolderPageProvider,
              folder.isRecursive != settings.isRecursiveFolder else { return }
        open(bookURL, failure: .notice, recordHistory: false)
    }

    /// 名前↑ は取得元の既定の並び（フォルダ・ZIP は自然順、PDF はページ順）なので並べ替えない
    private static func sorted(_ provider: PageProvider, mode: PageSortMode) -> PageProvider {
        mode == .fileName ? provider : SortedPageProvider(base: provider, mode: mode, seed: .random(in: 1...UInt64.max))
    }

    private func installProvider(_ provider: PageProvider, sortMode: PageSortMode, startIndex: Int) {
        appliedSortMode = sortMode
        bookURL = nil
        loaderTask?.cancel()
        loaderTask = nil
        loadQueue = []
        cache.removeAll()
        cacheRevision += 1
        pageThumbnails.reset { index in
            try provider.loadImage(at: index, maxPixelSize: ThumbnailSize.pixels).cgImage
        }
        failedPages = [:]
        widePages = [:]
        pageSizes = [:]
        pageEdgeColors = [:]
        self.provider = provider
        move(to: min(max(0, startIndex), max(0, provider.pageCount - 1)), part: nil)
        scheduleLoads()
    }

    // MARK: - ページ送り

    /// 次のページ（見開きでは次の組）へ。末尾では何もしない。
    func goNext() {
        moveSpread(by: 1)
    }

    /// 前のページ（見開きでは前の組）へ。先頭では何もしない。
    /// `atEnd` なら前のページを終わりの位置（下端・読み終わりの側）から表示する。
    func goPrevious(atEnd: Bool = false) {
        if atEnd { pendingOrigin = .end }
        moveSpread(by: -1)
        pendingOrigin = nil
    }

    /// 画面の左側のページへ（右開きでは次、左開きでは前）
    func goLeft() {
        readingDirection == .rightToLeft ? goNext() : goPrevious()
    }

    /// 画面の右側のページへ（右開きでは前、左開きでは次）
    func goRight() {
        readingDirection == .rightToLeft ? goPrevious() : goNext()
    }

    /// 指定ページへ（ページスライダーなど）
    func go(to page: Int) {
        guard (0..<pageCount).contains(page), page != currentIndex else { return }
        move(to: page, part: nil)
        scheduleLoads()
    }

    /// 開いている本を読み込み直す（NeeView の「再読み込み」）。現在のページは維持する。
    func reload() {
        guard let bookURL else { return }
        open(bookURL)
    }

    /// 先頭の組へ
    func goFirst() {
        guard let first = spreads.first, first != currentSpread else { return }
        move(to: first.first, part: first.part)
        scheduleLoads()
    }

    /// 末尾の組へ
    func goLast() {
        guard let last = spreads.last, currentSpread != last else { return }
        move(to: last.first, part: last.part)
        scheduleLoads()
    }

    private func moveSpread(by offset: Int) {
        let spreads = spreads
        guard let index = SpreadCalculator.spreadIndex(containing: currentIndex, part: currentPart, in: spreads) else { return }
        let target = index + offset
        guard spreads.indices.contains(target) else { return }
        move(to: spreads[target].first, part: spreads[target].part)
        scheduleLoads()
    }

    /// 表示するページ（と分割したページの半分）を変える
    private func move(to index: Int, part: PagePart?) {
        // ユーザーの操作でページを変えたら、スライドショーのタイマーを最初から数え直す
        if !isSlideShowAdvancing, index != currentIndex || part != currentPart { resetSlideShowTimer() }
        let origin = pendingOrigin
        currentIndex = index
        pendingOrigin = origin
        currentPart = part
        pendingOrigin = nil
    }

    /// ページを変えたら拡大・回転・反転・ルーペを元に戻す（NeeView の既定）
    private func resetTransformForNewPage() {
        transform = ViewTransform(origin: pendingOrigin ?? .start)
        pendingOrigin = nil
        isLoupeActive = false
    }

    // MARK: - 画像の読み込み

    /// 読み込む画像の長辺（ピクセル）。表示中のページの表示上の長辺に画面の倍率（とルーペの倍率）を掛け、256 単位に切り上げる。
    /// 少しのウィンドウサイズ変更で読み直さないようにするため。
    var requiredPixelSize: Int {
        guard containerSize.width > 0, containerSize.height > 0 else { return Self.screenMaxPixelSize() }
        let canvas = canvas
        let longest = canvas.pages.map { max($0.size.width, $0.size.height) * canvas.scale }.max()
            ?? max(containerSize.width, containerSize.height)
        let pixels = longest * (isLoupeActive ? loupeScale : 1) * displayScale
        return min(Self.originalMaxPixelSize, max(256, Int((pixels / 256).rounded(.up)) * 256))
    }

    /// 読み込む長辺の上限（ピクセル）。これより大きく表示するときは拡大して表示する
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
            let result: Result<(PageImage, CGColor?), Error> = await Task.detached(priority: .userInitiated) {
                Result {
                    let image = try provider.loadImage(at: index, maxPixelSize: maxPixelSize)
                    return (image, ImageLoading.edgeColor(of: image.cgImage))
                }
            }.value
            // 読み込み中に別の本を開いた場合は捨てる
            guard !Task.isCancelled, self.provider === provider else { return }
            switch result {
            case .success(let (image, edgeColor)):
                cache.insert(image, for: index, maxPixelSize: maxPixelSize)
                cacheRevision += 1
                if pageSizes[index] != image.pointSize { pageSizes[index] = image.pointSize }
                if let edgeColor { pageEdgeColors[index] = edgeColor }
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

    // MARK: - 表示サイズ・拡大縮小・回転・反転（NeeView のナビゲーター）

    /// 読み込み前のページの仮の大きさ（一般的な漫画のページの縦横比）
    static let placeholderPageSize = CGSize(width: 700, height: 1000)

    var canvas: Canvas {
        let pages = displayedPages
        // 分割したページは、画像の半分の大きさのページとして並べる
        let half = currentSpread?.part?.side(direction: readingDirection)
        let (sizes, frame) = CanvasLayout.frame(pageSizes: pages.map { page in
            let size = pageSizes[page] ?? Self.placeholderPageSize
            return half == nil ? size : CGSize(width: size.width / 2, height: size.height)
        })
        let stretch = CanvasLayout.stretchScale(
            mode: settings.stretchMode, frame: frame, angle: transform.angle, canvas: containerSize,
            allowScaleUp: settings.allowScaleUp, allowScaleDown: settings.allowScaleDown
        )
        let scale = stretch * transform.scale
        let content = CanvasLayout.rotatedBounds(
            CGSize(width: frame.width * scale, height: frame.height * scale), angle: transform.angle
        )
        let origin = CanvasLayout.originOffset(
            content: content, canvas: containerSize, origin: transform.origin, direction: readingDirection
        )
        let offset = CanvasLayout.clampOffset(
            CGSize(width: origin.width + transform.pan.width, height: origin.height + transform.pan.height),
            content: content, canvas: containerSize
        )
        return Canvas(
            pages: zip(pages, sizes).map { Canvas.Page(index: $0, size: $1, half: half) },
            frame: frame, stretchScale: stretch, scale: scale, content: content, offset: offset
        )
    }

    /// 背景「画像に合わせた色」のときの色（表示中の最初のページの縁の色）
    var autoBackgroundColor: CGColor? {
        displayedPages.lazy.compactMap { self.pageEdgeColors[$0] }.first
    }

    /// 表示サイズのモードを変える。ユーザーの拡大率と移動はリセットする。
    func setStretchMode(_ mode: PageStretchMode) {
        settings.stretchMode = mode
        transform.scale = 1
        transform.pan = .zero
        scheduleLoads()
    }

    func setAllowScaleUp(_ allow: Bool) {
        settings.allowScaleUp = allow
        scheduleLoads()
    }

    func setAllowScaleDown(_ allow: Bool) {
        settings.allowScaleDown = allow
        scheduleLoads()
    }

    /// 拡大率を変える刻み（NeeView の ViewScaleUp / ViewScaleDown の既定 20%）
    static let scaleStep: CGFloat = 0.2

    /// 表示上の拡大率（ストレッチ込み）。ナビゲーターの「スケール」に表示する
    var displayedScale: CGFloat { canvas.scale }

    /// 拡大（ストレッチ込みの拡大率が 100% をまたぐときは 100% で止める。NeeView の IsSnapDefaultScale）
    func zoomIn() {
        setDisplayedScale(snap(displayedScale, to: displayedScale * (1 + Self.scaleStep)))
    }

    func zoomOut() {
        setDisplayedScale(snap(displayedScale, to: displayedScale / (1 + Self.scaleStep)))
    }

    private func snap(_ old: CGFloat, to new: CGFloat) -> CGFloat {
        (old < 1 && new > 1) || (old > 1 && new < 1) ? 1 : new
    }

    /// 表示上の拡大率を指定する（ストレッチ込み）
    func setDisplayedScale(_ value: CGFloat) {
        let stretch = canvas.stretchScale
        guard stretch > 0 else { return }
        transform.scale = min(ViewTransform.maxScale, max(ViewTransform.minScale, value / stretch))
        clampPan()
    }

    /// ピンチなどで、ユーザーの拡大率を直接指定する
    func setUserScale(_ value: CGFloat) {
        transform.scale = min(ViewTransform.maxScale, max(ViewTransform.minScale, value))
        clampPan()
    }

    func resetScale() {
        transform.scale = 1
        clampPan()
    }

    func rotateLeft() { setAngle(transform.angle - 90) }
    func rotateRight() { setAngle(transform.angle + 90) }

    /// 回転角度を指定する（-180〜180 度に丸める）
    func setAngle(_ angle: Double) {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized > 180 { normalized -= 360 }
        if normalized <= -180 { normalized += 360 }
        transform.angle = normalized
        clampPan()
        scheduleLoads()
    }

    func resetAngle() { setAngle(0) }

    func toggleFlipHorizontal() { transform.flipHorizontal.toggle() }
    func toggleFlipVertical() { transform.flipVertical.toggle() }

    /// 拡大・回転・反転・移動をすべて元に戻す（NeeView の ViewReset）
    func resetView() {
        transform = ViewTransform()
        scheduleLoads()
    }

    /// ドラッグで画像を動かす
    func pan(by delta: CGSize) {
        transform.pan.width += delta.width
        transform.pan.height += delta.height
        clampPan()
    }

    /// 移動量を、表示領域から離れすぎない範囲に収める
    private func clampPan() {
        let canvas = canvas
        let origin = CanvasLayout.originOffset(
            content: canvas.content, canvas: containerSize, origin: transform.origin, direction: readingDirection
        )
        transform.pan = CGSize(width: canvas.offset.width - origin.width, height: canvas.offset.height - origin.height)
    }

    /// スクロールの1回分の操作。画像が表示領域からはみ出していればその中を移動し、端まで来たらページを送る
    /// （NeeView の NextScrollPage / PrevScrollPage と N字スクロール）。はみ出していなければすぐにページを送る。
    func scroll(_ action: ScrollPager.Action) {
        if isLoupeActive {
            // ルーペ中のホイールはルーペの倍率を変える（NeeView の LoupeScaleUp / LoupeScaleDown）
            loupeScale = min(10, max(1, loupeScale + (action == .previous ? 1 : -1)))
            scheduleLoads()
            return
        }
        let canvas = canvas
        let overX = max(0, (canvas.content.width - containerSize.width) / 2)
        let overY = max(0, (canvas.content.height - containerSize.height) / 2)
        let stepY = containerSize.height * 0.8
        let stepX = containerSize.width * 0.8
        // 読み進める向きの横移動：右開きは内容を右へ（offset を増やす）
        let forwardX: CGFloat = readingDirection == .rightToLeft ? 1 : -1
        let epsilon: CGFloat = 0.5
        let offset = canvas.offset

        switch action {
        case .next:
            if overY > epsilon, offset.height > -overY + epsilon {
                pan(by: CGSize(width: 0, height: -stepY))
            } else if overX > epsilon, offset.width * forwardX < overX - epsilon {
                // 横に進み、縦は上端へ戻る（N字）
                pan(by: CGSize(width: stepX * forwardX, height: overY * 2))
            } else {
                goNext()
            }
        case .previous:
            if overY > epsilon, offset.height < overY - epsilon {
                pan(by: CGSize(width: 0, height: stepY))
            } else if overX > epsilon, offset.width * forwardX > -overX + epsilon {
                pan(by: CGSize(width: -stepX * forwardX, height: -overY * 2))
            } else {
                goPrevious(atEnd: true)
            }
        }
    }

    // MARK: - スライドショー（NeeView の SlideShow。既定：5 秒、ループ再生、自動スクロール）

    func toggleSlideShow() {
        isSlideShowPlaying ? stopSlideShow() : startSlideShow()
    }

    func startSlideShow() {
        guard isBookOpen else { return }
        isSlideShowPlaying = true
        resetSlideShowTimer()
    }

    func stopSlideShow() {
        isSlideShowPlaying = false
        slideShowTask?.cancel()
        slideShowTask = nil
    }

    /// キーボード・マウスの操作があったら、次のスライドまでの時間を数え直す（NeeView の既定 InputAction）
    func resetSlideShowTimer() {
        guard isSlideShowPlaying else { return }
        slideShowTask?.cancel()
        let interval = settings.slideShowInterval
        slideShowTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.advanceSlideShow()
            }
        }
    }

    /// スライドショーを1回分進める。画像がはみ出していればその中をスクロールし（NeeView の IsAutoScroll）、
    /// 最後のページではループ再生なら先頭へ戻り、そうでなければ停止する。
    func advanceSlideShow() {
        guard isSlideShowPlaying, isBookOpen else {
            stopSlideShow()
            return
        }
        isSlideShowAdvancing = true
        defer { isSlideShowAdvancing = false }
        let before = (currentIndex, currentPart, transform.pan)
        scroll(.next)
        guard before == (currentIndex, currentPart, transform.pan) else { return }
        if settings.isSlideShowByLoop {
            goFirst()
        } else {
            stopSlideShow()
        }
    }
}
