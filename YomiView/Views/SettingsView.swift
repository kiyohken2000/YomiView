import SwiftUI

/// 設定画面（⌘,）。
struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Picker("開き方向", selection: $settings.readingDirection) {
                ForEach(ReadingDirection.allCases) { direction in
                    Text(direction.label).tag(direction)
                }
            }
            .pickerStyle(.radioGroup)

            Section("見開き") {
                Toggle("表紙（1ページ目）を単独で表示する", isOn: $settings.coverSingle)
                Toggle("最後のページを単独で表示する", isOn: $settings.lastSingle)
                Toggle("横長のページを単独で表示する", isOn: $settings.landscapeSingle)
                Toggle("1ページ表示のとき、横長のページを分割する", isOn: $settings.dividePage)
            }

            Section("ページ") {
                Picker("ページの並び順", selection: $settings.pageSortMode) {
                    ForEach(PageSortMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("フォルダのサブフォルダーを読み込む", isOn: $settings.isRecursiveFolder)
                Toggle("前回開いたページから開く", isOn: $settings.isRestoreLastPage)
            }

            Section("スライドショー") {
                LabeledContent("スライドを切り替える時間 (秒)") {
                    HStack {
                        TextField("", value: $settings.slideShowInterval, format: .number.precision(.fractionLength(0...1)))
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $settings.slideShowInterval, in: AppSettings.slideShowIntervalRange, step: 0.5)
                            .labelsHidden()
                    }
                }
                Toggle("ループ再生", isOn: $settings.isSlideShowByLoop)
            }

            Section("ウィンドウ") {
                Toggle("フルスクリーンで自動非表示モードを適用する", isOn: $settings.isAutoHideInFullScreen)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
