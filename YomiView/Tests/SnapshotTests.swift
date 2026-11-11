import AppKit
import SwiftUI
import XCTest
@testable import YomiView

/// 画面の見た目を確認するためのスナップショット。
///
/// 環境変数 `YOMIVIEW_SNAPSHOT_DIR`（xcodebuild からは `TEST_RUNNER_YOMIVIEW_SNAPSHOT_DIR`）と
/// `YOMIVIEW_SNAPSHOT_BOOK` を指定したときだけ動き、ウィンドウを PNG に書き出す。通常のテストでは何もしない。
/// `YOMIVIEW_SNAPSHOT_WIDE_BOOK`（2ページ目が横長の本）も指定すると、横長ページの分割も書き出す。
@MainActor
final class SnapshotTests: XCTestCase {
    func testWriteMainWindowSnapshots() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["YOMIVIEW_SNAPSHOT_DIR"], let book = env["YOMIVIEW_SNAPSHOT_BOOK"] else {
            throw XCTSkip("スナップショットは環境変数を指定したときだけ書き出す")
        }
        let outDir = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // 本物の設定・履歴を汚さないよう、専用の保存先を使う
        let suiteName = "YomiViewSnapshot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let layout = SidePanelLayout(defaults: defaults)
        let settings = AppSettings(defaults: defaults)
        let recentBooks = RecentBooksStore(defaults: defaults)

        var snapshots: [(String, CGSize, SidePanelKind?, SidePanelKind?, Bool, (ReaderViewModel) -> Void)] = [
            ("spread-panels", CGSize(width: 1280, height: 800), .bookshelf, .fileInfo, true, { _ in }),
            ("pagelist", CGSize(width: 1280, height: 800), .pageList, nil, false, { _ in }),
            ("single", CGSize(width: 800, height: 1000), nil, nil, false, { _ in }),
            ("navigator", CGSize(width: 1280, height: 800), nil, .navigator, false, { viewModel in
                viewModel.settings.background = .checkDark
                viewModel.rotateRight()
                viewModel.toggleFlipHorizontal()
            }),
        ]
        if let wide = env["YOMIVIEW_SNAPSHOT_WIDE_BOOK"] {
            // 右開きの1ページ表示で横長ページを分割：まず右半分（R）、次に左半分（L）
            for (name, steps) in [("divide-first", 0), ("divide-second", 1)] {
                snapshots.append((name, CGSize(width: 800, height: 1000), nil, nil, false, { viewModel in
                    viewModel.settings.dividePage = true
                    viewModel.manualViewMode = .single
                    viewModel.open(URL(fileURLWithPath: wide))
                    viewModel.goNext()
                    Task { @MainActor in
                        // 横長と分かって分割されるまで待ってから進める
                        for _ in 0..<40 where viewModel.currentPart == nil { try? await Task.sleep(nanoseconds: 20_000_000) }
                        for _ in 0..<steps { viewModel.goNext() }
                    }
                }))
            }
        }
        for (name, size, left, right, filmStrip, configure) in snapshots {
            layout.left = left
            layout.right = right
            settings.isFilmStripVisible = filmStrip
            let viewModel = ReaderViewModel(settings: settings, recentBooks: recentBooks)
            viewModel.open(URL(fileURLWithPath: book))
            viewModel.goNext()
            configure(viewModel)
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: size),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false
            )
            window.contentView = NSHostingView(rootView: ReaderView(viewModel: viewModel, panelLayout: layout))
            window.appearance = NSAppearance(named: .darkAqua)
            window.orderFront(nil)
            for _ in 0..<30 {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            let view = try XCTUnwrap(window.contentView)
            view.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: outDir.appendingPathComponent("\(name).png"))
            window.orderOut(nil)
            settings.background = .black
            settings.dividePage = false
        }
    }
}
