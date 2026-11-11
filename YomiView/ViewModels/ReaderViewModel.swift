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

    let settings: AppSettings

    private(set) var provider: PageProvider?
    /// 現在のページ（表示中の組に含まれるページ）
    private(set) var currentIndex: Int = 0
    /// 読み込み済み・失敗したページの状態
    private(set) var pageStates: [Int: PageState] = [:]
    /// 読み込んで分かった、各ページが横長かどうか
    private(set) var widePages: [Int: Bool] = [:]
    /// M キーなどで手動で選んだ表示モード。nil なら表示領域の形で自動的に決める
    var manualViewMode: ViewMode?
    /// 表示領域の大きさ（ポイント）
    private(set) var containerSize: CGSize = .zero
    /// 本を開けなかったときのエラー（アラート表示用）
    var openError: String?

    @ObservationIgnored private var loadQueue: [Int] = []
    @ObservationIgnored private var loaderTask: Task<Void, Never>?

    init(settings: AppSettings = .shared) {
        self.settings = settings
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
        pageStates[page] ?? .loading
    }

    /// ウィンドウタイトル（本の名前と現在ページ）
    var windowTitle: String {
        guard let provider, let spread = currentSpread else { return "YomiView" }
        let pages = spread.pages.count > 1 ? "\(spread.first + 1)-\(spread.last + 1)" : "\(spread.first + 1)"
        return "\(provider.title) (\(pages) / \(provider.pageCount))"
    }

    func updateContainerSize(_ size: CGSize) {
        guard size != containerSize else { return }
        containerSize = size
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

    func open(_ url: URL) {
        do {
            let provider = try BookSource.detect(url).makeProvider()
            setProvider(provider)
        } catch {
            openError = error.localizedDescription
        }
    }

    /// 開いた本を設定し、指定ページ（既定は先頭）を表示する。
    func setProvider(_ provider: PageProvider, startIndex: Int = 0) {
        loaderTask?.cancel()
        loaderTask = nil
        loadQueue = []
        pageStates = [:]
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

    private func moveSpread(by offset: Int) {
        let spreads = spreads
        guard let index = SpreadCalculator.spreadIndex(containing: currentIndex, in: spreads) else { return }
        let target = index + offset
        guard spreads.indices.contains(target) else { return }
        currentIndex = spreads[target].first
        scheduleLoads()
    }

    // MARK: - 画像の読み込み

    /// 読み込むときの長辺の上限（ピクセル）。画面の長辺に合わせる。
    nonisolated static func displayMaxPixelSize() -> Int {
        let sizes = NSScreen.screens.map { screen in
            max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor
        }
        return Int(sizes.max() ?? 2048)
    }

    /// 表示中のページを読み込む。表示に関わる状態が変わるたびに呼ぶ。
    func scheduleLoads() {
        guard let currentSpread else { return }
        let wanted = currentSpread.pages
        // 表示しないページの画像は持たない
        pageStates = pageStates.filter { wanted.contains($0.key) }
        loadQueue = wanted.filter { pageStates[$0] == nil }
        if loaderTask == nil, !loadQueue.isEmpty {
            loaderTask = Task { [weak self] in await self?.runLoader() }
        }
    }

    private func runLoader() async {
        defer { loaderTask = nil }
        while !Task.isCancelled, !loadQueue.isEmpty, let provider {
            let index = loadQueue.removeFirst()
            guard pageStates[index] == nil else { continue }
            let maxPixelSize = Self.displayMaxPixelSize()
            let result: Result<PageImage, Error> = await Task.detached(priority: .userInitiated) {
                Result { try provider.loadImage(at: index, maxPixelSize: maxPixelSize) }
            }.value
            // 読み込み中に別の本を開いた場合は捨てる
            guard !Task.isCancelled, self.provider === provider else { return }
            guard currentSpread?.contains(index) == true else { continue }
            switch result {
            case .success(let image):
                pageStates[index] = .loaded(image)
                if widePages[index] != image.isWide {
                    widePages[index] = image.isWide
                    // 横長と分かったことで組み合わせが変わる場合がある
                    scheduleLoads()
                }
            case .failure(let error):
                pageStates[index] = .failed(error.localizedDescription)
            }
        }
    }
}
