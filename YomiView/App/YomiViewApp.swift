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
    }
}

/// ファイルメニュー。
struct ReaderCommands: Commands {
    @FocusedValue(\.readerViewModel) private var viewModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("開く…") { viewModel?.presentOpenPanel() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(viewModel == nil)
        }
    }
}
