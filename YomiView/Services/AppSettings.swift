import Foundation
import Observation

/// アプリ全体の設定。UserDefaults に保存する。
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings(defaults: .standard)

    private enum Key {
        static let readingDirection = "readingDirection"
        static let coverSingle = "coverSingle"
        static let landscapeSingle = "landscapeSingle"
        static let isFilmStripVisible = "isFilmStripVisible"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// 開き方向（初期値は右開き）
    var readingDirection: ReadingDirection {
        didSet { defaults.set(readingDirection.rawValue, forKey: Key.readingDirection) }
    }

    /// 見開きで表紙を単独表示する（初期値オン）
    var coverSingle: Bool {
        didSet { defaults.set(coverSingle, forKey: Key.coverSingle) }
    }

    /// 見開きで横長のページを単独表示する（初期値オン）
    var landscapeSingle: Bool {
        didSet { defaults.set(landscapeSingle, forKey: Key.landscapeSingle) }
    }

    /// フィルムストリップを表示する（NeeView の既定どおりオフ）
    var isFilmStripVisible: Bool {
        didSet { defaults.set(isFilmStripVisible, forKey: Key.isFilmStripVisible) }
    }

    var spreadOptions: SpreadCalculator.Options {
        SpreadCalculator.Options(coverSingle: coverSingle, landscapeSingle: landscapeSingle)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        readingDirection = defaults.string(forKey: Key.readingDirection)
            .flatMap(ReadingDirection.init(rawValue:)) ?? .rightToLeft
        coverSingle = defaults.object(forKey: Key.coverSingle) as? Bool ?? true
        landscapeSingle = defaults.object(forKey: Key.landscapeSingle) as? Bool ?? true
        isFilmStripVisible = defaults.object(forKey: Key.isFilmStripVisible) as? Bool ?? false
    }
}
