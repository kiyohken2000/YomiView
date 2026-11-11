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
        static let lastSingle = "lastSingle"
        static let dividePage = "dividePage"
        static let pageSortMode = "pageSortMode"
        static let isRecursiveFolder = "isRecursiveFolder"
        static let slideShowInterval = "slideShowInterval"
        static let isSlideShowByLoop = "isSlideShowByLoop"
        static let isAutoHideInFullScreen = "isAutoHideInFullScreen"
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

    /// 見開きで最後のページを単独表示する（NeeView の既定どおりオフ）
    var lastSingle: Bool {
        didSet { defaults.set(lastSingle, forKey: Key.lastSingle) }
    }

    /// 1ページ表示で横長ページを分割する（NeeView の既定どおりオフ）
    var dividePage: Bool {
        didSet { defaults.set(dividePage, forKey: Key.dividePage) }
    }

    /// ページの並び順（計画書どおり名前の自然順が初期値）
    var pageSortMode: PageSortMode {
        didSet { defaults.set(pageSortMode.rawValue, forKey: Key.pageSortMode) }
    }

    /// フォルダを開くときサブフォルダの画像も読み込む（NeeView の既定どおりオフ）
    var isRecursiveFolder: Bool {
        didSet { defaults.set(isRecursiveFolder, forKey: Key.isRecursiveFolder) }
    }

    /// スライドを切り替える時間（秒。NeeView の既定 5 秒、0.1〜30 秒）
    var slideShowInterval: Double {
        didSet {
            let clamped = Self.clampInterval(slideShowInterval)
            if clamped != slideShowInterval { slideShowInterval = clamped; return }
            defaults.set(slideShowInterval, forKey: Key.slideShowInterval)
        }
    }

    static let slideShowIntervalRange: ClosedRange<Double> = 0.1...30

    private static func clampInterval(_ value: Double) -> Double {
        min(slideShowIntervalRange.upperBound, max(slideShowIntervalRange.lowerBound, value))
    }

    /// スライドショーのループ再生（最後まで再生したら先頭に戻る。NeeView の既定オン）
    var isSlideShowByLoop: Bool {
        didSet { defaults.set(isSlideShowByLoop, forKey: Key.isSlideShowByLoop) }
    }

    /// フルスクリーンでアドレスバー・パネル・スライダーを自動的に隠す（NeeView の既定オン）
    var isAutoHideInFullScreen: Bool {
        didSet { defaults.set(isAutoHideInFullScreen, forKey: Key.isAutoHideInFullScreen) }
    }

    var spreadOptions: SpreadCalculator.Options {
        SpreadCalculator.Options(
            coverSingle: coverSingle, landscapeSingle: landscapeSingle,
            lastSingle: lastSingle, dividePage: dividePage
        )
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
        lastSingle = defaults.object(forKey: Key.lastSingle) as? Bool ?? false
        dividePage = defaults.object(forKey: Key.dividePage) as? Bool ?? false
        pageSortMode = defaults.string(forKey: Key.pageSortMode).flatMap(PageSortMode.init(rawValue:)) ?? .fileName
        isRecursiveFolder = defaults.object(forKey: Key.isRecursiveFolder) as? Bool ?? false
        slideShowInterval = Self.clampInterval(defaults.object(forKey: Key.slideShowInterval) as? Double ?? 5)
        isSlideShowByLoop = defaults.object(forKey: Key.isSlideShowByLoop) as? Bool ?? true
        isAutoHideInFullScreen = defaults.object(forKey: Key.isAutoHideInFullScreen) as? Bool ?? true
    }
}
