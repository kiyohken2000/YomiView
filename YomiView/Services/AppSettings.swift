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
        static let stretchMode = "stretchMode"
        static let allowScaleUp = "allowScaleUp"
        static let allowScaleDown = "allowScaleDown"
        static let background = "background"
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

    /// 表示サイズのモード（NeeView の既定どおりウィンドウに合わせる）
    var stretchMode: PageStretchMode {
        didSet { defaults.set(stretchMode.rawValue, forKey: Key.stretchMode) }
    }

    /// ストレッチで拡大を許可する（NeeView の既定オン）
    var allowScaleUp: Bool {
        didSet { defaults.set(allowScaleUp, forKey: Key.allowScaleUp) }
    }

    /// ストレッチで縮小を許可する（NeeView の既定オン）
    var allowScaleDown: Bool {
        didSet { defaults.set(allowScaleDown, forKey: Key.allowScaleDown) }
    }

    /// 背景（NeeView の既定どおり黒）
    var background: BackgroundType {
        didSet { defaults.set(background.rawValue, forKey: Key.background) }
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
        stretchMode = defaults.string(forKey: Key.stretchMode).flatMap(PageStretchMode.init(rawValue:)) ?? .uniform
        allowScaleUp = defaults.object(forKey: Key.allowScaleUp) as? Bool ?? true
        allowScaleDown = defaults.object(forKey: Key.allowScaleDown) as? Bool ?? true
        background = defaults.string(forKey: Key.background).flatMap(BackgroundType.init(rawValue:)) ?? .black
    }
}
