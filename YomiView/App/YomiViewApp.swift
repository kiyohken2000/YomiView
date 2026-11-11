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

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("開く…") { viewModel?.presentOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(viewModel == nil)
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
