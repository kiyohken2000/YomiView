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
                Toggle("横長のページを単独で表示する", isOn: $settings.landscapeSingle)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
