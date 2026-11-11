import AppKit
import SwiftUI

/// 置かれたウィンドウがフルスクリーンかどうかを知らせる。
struct FullScreenObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            // 切り替えが始まった時点で画面の構成を変える
            let changes: [(Notification.Name, Bool)] = [
                (NSWindow.willEnterFullScreenNotification, true),
                (NSWindow.willExitFullScreenNotification, false),
            ]
            observers = changes.map { name, isFullScreen in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onChange?(isFullScreen) }
                }
            }
            // 最初からフルスクリーンのとき（ウィンドウの復元など）だけ知らせる
            if window.styleMask.contains(.fullScreen) {
                DispatchQueue.main.async { [weak self] in self?.onChange?(true) }
            }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

/// フルスクリーンの自動非表示（NeeView の AutoHide）：画面の端にマウスを近づけたところだけ表示する。
struct AutoHideState {
    /// 端からこの距離に近づいたら表示する（NeeView の AutoHideHitTestMargin の既定 32）
    static let margin: CGFloat = 32
    /// 離れてから隠すまでの時間（NeeView の AutoHideDelayTime の既定 1 秒）
    static let hideDelay: UInt64 = 1_000_000_000

    enum Edge: CaseIterable, Hashable {
        case top, bottom, left, right
    }

    /// 表示している端
    var visible: Set<Edge> = []
    /// 表示している要素の大きさ（端からの奥行き）
    var depths: [Edge: CGFloat] = [:]

    /// マウスの位置で表示すべき端。表示中の要素の上にいる間は表示し続ける。
    func edges(at location: CGPoint?, in size: CGSize) -> Set<Edge> {
        // 大きさがまだ分からないうちは何も表示しない
        guard let location, size.width > 0, size.height > 0 else { return [] }
        func depth(_ edge: Edge) -> CGFloat {
            max(Self.margin, visible.contains(edge) ? depths[edge] ?? 0 : 0)
        }
        var result: Set<Edge> = []
        if location.y <= depth(.top) { result.insert(.top) }
        if location.y >= size.height - depth(.bottom) { result.insert(.bottom) }
        if location.x <= depth(.left) { result.insert(.left) }
        if location.x >= size.width - depth(.right) { result.insert(.right) }
        return result
    }
}
