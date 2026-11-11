import Foundation

/// 本の開き方向。
enum ReadingDirection: String, CaseIterable, Identifiable {
    /// 左開き（左から右へ読む。横書きの本）
    case leftToRight
    /// 右開き（右から左へ読む。日本の漫画）
    case rightToLeft

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leftToRight: return "左開き"
        case .rightToLeft: return "右開き"
        }
    }

    var toggled: ReadingDirection {
        self == .leftToRight ? .rightToLeft : .leftToRight
    }
}
