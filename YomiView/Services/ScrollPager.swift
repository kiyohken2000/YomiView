import Foundation

/// 上下スクロールをページ送りに変換する。副作用を持たず、イベントの値だけで判断する。
///
/// - トラックパッド（フェーズのあるスクロール）：1回の操作（指を置いてから離すまで）で1ページだけ送る。慣性スクロールは無視する。
/// - マウスホイール（フェーズのないスクロール）：1回の回転で1ページ。続けて回したときは一定間隔ごとに1ページ。
struct ScrollPager {
    enum Action: Equatable {
        case next
        case previous
    }

    enum Phase {
        /// フェーズなし（マウスホイール）
        case none
        case began
        case changed
        case ended
    }

    /// トラックパッドで1ページ送るのに必要なスクロール量（ポイント）
    var threshold: CGFloat = 12
    /// マウスホイールを続けて回したときに、ページを送る最短の間隔（秒）
    var wheelInterval: TimeInterval = 0.15

    private var accumulated: CGFloat = 0
    private var firedInGesture = false
    private var lastWheelTime: TimeInterval = -.infinity

    /// - Parameter deltaY: 縦方向のスクロール量。負の値が下方向（内容が上に動く）
    mutating func handle(deltaY: CGFloat, phase: Phase, isMomentum: Bool, timestamp: TimeInterval) -> Action? {
        if isMomentum { return nil }
        switch phase {
        case .none:
            guard deltaY != 0, timestamp - lastWheelTime >= wheelInterval else { return nil }
            lastWheelTime = timestamp
            return Self.action(for: deltaY)
        case .began, .changed:
            if phase == .began {
                accumulated = 0
                firedInGesture = false
            }
            accumulated += deltaY
            guard !firedInGesture, abs(accumulated) >= threshold else { return nil }
            firedInGesture = true
            return Self.action(for: accumulated)
        case .ended:
            accumulated = 0
            firedInGesture = false
            return nil
        }
    }

    /// 下へのスクロールは次のページ、上へは前のページ（開き方向に関係なく同じ）
    private static func action(for deltaY: CGFloat) -> Action {
        deltaY < 0 ? .next : .previous
    }
}
