import SwiftUI

@main
struct YomiViewApp: App {
    var body: some Scene {
        WindowGroup {
            ReaderView()
        }
        .defaultSize(width: 900, height: 1100)
        .commands {
            ReaderCommands()
        }

        Settings {
            SettingsView(settings: .shared)
        }
    }
}

/// ファイル・表示メニュー。
struct ReaderCommands: Commands {
    @FocusedValue(\.readerViewModel) private var viewModel
    private let recentBooks = RecentBooksStore.shared

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("開く…") { viewModel?.presentOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(viewModel == nil)
            Menu("最近開いた本") {
                ForEach(recentBooks.entries) { entry in
                    Button(entry.displayName) { viewModel?.open(entry.url) }
                        .disabled(viewModel == nil)
                }
                if !recentBooks.entries.isEmpty {
                    Divider()
                }
                Button("メニューを消去") { recentBooks.clear() }
                    .disabled(recentBooks.entries.isEmpty)
            }
        }
        CommandMenu("移動") {
            Button("次のブック") { viewModel?.openNextBook() }
                .keyboardShortcut(.downArrow, modifiers: .option)
            Button("前のブック") { viewModel?.openPreviousBook() }
                .keyboardShortcut(.upArrow, modifiers: .option)
            Divider()
            Button("戻る") { viewModel?.goBackBook() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(viewModel?.canGoBackBook != true)
            Button("進む") { viewModel?.goForwardBook() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(viewModel?.canGoForwardBook != true)
            Button("上の階層へ") { viewModel?.openParentBook() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(viewModel?.isBookOpen != true)
            Divider()
            Button("最初のページ（Home）") { viewModel?.goFirst() }
                .disabled(viewModel?.isBookOpen != true)
            Button("最後のページ（End）") { viewModel?.goLast() }
                .disabled(viewModel?.isBookOpen != true)
        }
        CommandGroup(before: .toolbar) {
            Button(viewModel?.viewMode == .spread ? "1ページ表示にする（M）" : "見開き表示にする（M）") {
                viewModel?.toggleViewMode()
            }
            .disabled(viewModel == nil)
            Button(AppSettings.shared.readingDirection == .rightToLeft ? "左開きにする（D）" : "右開きにする（D）") {
                AppSettings.shared.readingDirection = AppSettings.shared.readingDirection.toggled
            }
            Divider()
            Toggle("フィルムストリップ", isOn: Bindable(AppSettings.shared).isFilmStripVisible)
            Divider()
            Button("ウィンドウに合わせる") { viewModel?.zoomMode = .fit }
                .keyboardShortcut("9", modifiers: .command)
                .disabled(viewModel == nil || viewModel?.zoomMode == .fit)
            Button("原寸") { viewModel?.zoomMode = .original }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(viewModel == nil || viewModel?.zoomMode == .original)
            Divider()
        }
    }
}
