import Foundation

/// 1ページ表示 / 見開き表示。
enum ViewMode: String, CaseIterable, Identifiable {
    case single
    case spread

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: return "1ページ"
        case .spread: return "見開き"
        }
    }

    var toggled: ViewMode {
        self == .single ? .spread : .single
    }
}
