import AppKit
import SwiftUI

/// このビューを含むウィンドウのスクロールイベントを受け取り、ページ送りに変換する。
///
/// `isEnabled` が false のとき（原寸表示でスクロールして画像を見るとき）はイベントをそのまま流す。
struct ScrollWheelMonitor: NSViewRepresentable {
    var isEnabled: Bool
    var onAction: (ScrollPager.Action) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.isEnabled = isEnabled
        view.onAction = onAction
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.isEnabled = isEnabled
        view.onAction = onAction
    }

    final class MonitorView: NSView {
        var isEnabled = true
        var onAction: (ScrollPager.Action) -> Void = { _ in }
        private var pager = ScrollPager()
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                // このビューの範囲（本の表示領域）の上でのスクロールだけを扱う。パネルの一覧などはそのままスクロールさせる
                guard let self, self.isEnabled, event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                else { return event }
                if let action = self.pager.handle(
                    deltaY: event.scrollingDeltaY,
                    phase: Self.phase(of: event),
                    isMomentum: !event.momentumPhase.isEmpty,
                    timestamp: event.timestamp
                ) {
                    self.onAction(action)
                }
                return nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private static func phase(of event: NSEvent) -> ScrollPager.Phase {
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) { return .began }
            if event.phase.contains(.changed) || event.phase.contains(.stationary) { return .changed }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) { return .ended }
            return .none
        }
    }
}
