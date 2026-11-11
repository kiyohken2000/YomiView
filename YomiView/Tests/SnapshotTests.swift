import AppKit
import SwiftUI
import XCTest
@testable import YomiView

/// 画面の見た目を確認するためのスナップショット。
///
/// 環境変数 `YOMIVIEW_SNAPSHOT_DIR`（xcodebuild からは `TEST_RUNNER_YOMIVIEW_SNAPSHOT_DIR`）と
/// `YOMIVIEW_SNAPSHOT_BOOK` を指定したときだけ動き、ウィンドウを PNG に書き出す。通常のテストでは何もしない。
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

        let snapshots: [(String, CGSize, SidePanelKind?, SidePanelKind?, Bool)] = [
            ("spread-panels", CGSize(width: 1280, height: 800), .bookshelf, .fileInfo, true),
            ("pagelist", CGSize(width: 1280, height: 800), .pageList, nil, false),
            ("single", CGSize(width: 800, height: 1000), nil, nil, false),
        ]
        for (name, size, left, right, filmStrip) in snapshots {
            layout.left = left
            layout.right = right
            settings.isFilmStripVisible = filmStrip
            let viewModel = ReaderViewModel(settings: settings, recentBooks: recentBooks)
            viewModel.open(URL(fileURLWithPath: book))
            viewModel.goNext()
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
        }
    }
}
