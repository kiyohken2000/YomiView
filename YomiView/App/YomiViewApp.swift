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
        CommandMenu("ブックマーク") {
            Button(viewModel?.bookURL.map(BookmarkStore.shared.contains) == true ? "ブックマークから削除" : "ブックマークに登録") {
                if let url = viewModel?.bookURL { BookmarkStore.shared.toggle(url) }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(viewModel?.bookURL == nil)
            Button("ブックマークパネル") { SidePanelLayout.shared.toggle(.bookmark) }
                .keyboardShortcut("b", modifiers: [.command, .option])
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
        CommandMenu("ページ") {
            // 表示名は NeeView のページ設定に合わせる
            Toggle("最初のページを単独表示", isOn: Bindable(AppSettings.shared).coverSingle)
            Toggle("最後のページを単独表示", isOn: Bindable(AppSettings.shared).lastSingle)
            Toggle("横長ページを 2 ページとみなす", isOn: Bindable(AppSettings.shared).landscapeSingle)
            Toggle("横長ページを分割する", isOn: Bindable(AppSettings.shared).dividePage)
            Divider()
            Menu("ページの並び順") {
                ForEach(PageSortMode.allCases) { mode in
                    Toggle(mode.label, isOn: Binding(
                        get: { AppSettings.shared.pageSortMode == mode },
                        set: { if $0 { viewModel?.setPageSortMode(mode) ?? (AppSettings.shared.pageSortMode = mode) } }
                    ))
                }
            }
            Toggle("サブフォルダーを読み込む", isOn: Binding(
                get: { AppSettings.shared.isRecursiveFolder },
                set: { viewModel?.setRecursiveFolder($0) ?? (AppSettings.shared.isRecursiveFolder = $0) }
            ))
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
            Menu("ストレッチ") {
                ForEach(PageStretchMode.allCases) { mode in
                    Toggle(mode.label, isOn: Binding(
                        get: { AppSettings.shared.stretchMode == mode },
                        set: { if $0 { viewModel?.setStretchMode(mode) ?? (AppSettings.shared.stretchMode = mode) } }
                    ))
                }
            }
            Button("ウィンドウに合わせる") { viewModel?.setStretchMode(.uniform) }
                .keyboardShortcut("9", modifiers: .command)
            Button("オリジナル サイズ") { viewModel?.setStretchMode(.none) }
                .keyboardShortcut("0", modifiers: .command)
            Button("拡大") { viewModel?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(viewModel?.isBookOpen != true)
            Button("縮小") { viewModel?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(viewModel?.isBookOpen != true)
            Divider()
            Button("右回転") { viewModel?.rotateRight() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel?.isBookOpen != true)
            Button("左回転") { viewModel?.rotateLeft() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(viewModel?.isBookOpen != true)
            Button("左右反転") { viewModel?.toggleFlipHorizontal() }
                .disabled(viewModel?.isBookOpen != true)
            Button("上下反転") { viewModel?.toggleFlipVertical() }
                .disabled(viewModel?.isBookOpen != true)
            Button("表示をリセット") { viewModel?.resetView() }
                .disabled(viewModel?.isBookOpen != true)
            Divider()
            Picker("背景", selection: Bindable(AppSettings.shared).background) {
                ForEach(BackgroundType.allCases) { Text($0.label).tag($0) }
            }
            Divider()
        }
    }
}
