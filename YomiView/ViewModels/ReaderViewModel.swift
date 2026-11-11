import AppKit
import Foundation
import Observation

/// 表示中の本と現在ページの状態。View はこの状態を表示するだけにする。
@MainActor
@Observable
final class ReaderViewModel {
    /// 現在ページの表示状態
    enum PageState: Equatable {
        case empty
        case loading
        case loaded(PageImage)
        case failed(String)

        static func == (lhs: PageState, rhs: PageState) -> Bool {
            switch (lhs, rhs) {
            case (.empty, .empty), (.loading, .loading): return true
            case let (.loaded(a), .loaded(b)): return a.cgImage === b.cgImage
            case let (.failed(a), .failed(b)): return a == b
            default: return false
            }
        }
    }

    private(set) var provider: PageProvider?
    private(set) var currentIndex: Int = 0
    private(set) var pageState: PageState = .empty
    /// 本を開けなかったときのエラー（アラート表示用）
    var openError: String?

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    var isBookOpen: Bool { provider != nil }
    var pageCount: Int { provider?.pageCount ?? 0 }

    /// ウィンドウタイトル（本の名前と現在ページ）
    var windowTitle: String {
        guard let provider else { return "YomiView" }
        return "\(provider.title) (\(currentIndex + 1) / \(provider.pageCount))"
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

    /// 開いた本を設定し、先頭ページを表示する。
    func setProvider(_ provider: PageProvider) {
        self.provider = provider
        currentIndex = 0
        loadCurrentPage()
    }

    // MARK: - ページ送り

    /// 次のページへ。末尾では何もしない。
    func goNext() {
        go(to: currentIndex + 1)
    }

    /// 前のページへ。先頭では何もしない。
    func goPrevious() {
        go(to: currentIndex - 1)
    }

    func go(to index: Int) {
        guard let provider, provider.pages.indices.contains(index), index != currentIndex else { return }
        currentIndex = index
        loadCurrentPage()
    }

    // MARK: - 画像の読み込み

    /// 読み込むときの長辺の上限（ピクセル）。画面の長辺に合わせる。
    nonisolated static func displayMaxPixelSize() -> Int {
        let sizes = NSScreen.screens.map { screen in
            max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor
        }
        return Int(sizes.max() ?? 2048)
    }

    private func loadCurrentPage() {
        loadTask?.cancel()
        guard let provider else {
            pageState = .empty
            return
        }
        let index = currentIndex
        let maxPixelSize = Self.displayMaxPixelSize()
        pageState = .loading
        loadTask = Task { [weak self] in
            let result: Result<PageImage, Error> = await Task.detached(priority: .userInitiated) {
                Result { try provider.loadImage(at: index, maxPixelSize: maxPixelSize) }
            }.value
            guard let self, !Task.isCancelled, self.currentIndex == index, self.provider === provider else { return }
            switch result {
            case .success(let image):
                self.pageState = .loaded(image)
            case .failure(let error):
                self.pageState = .failed(error.localizedDescription)
            }
        }
    }
}
