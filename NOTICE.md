# NOTICE

## NeeView

YomiView は Windows 向け画像ビューア「NeeView」（Copyright (c) 2016-2026 Ito Mitsuhiro (nee), MIT License）の
中核機能を参考に、macOS 向けに新たに実装したアプリケーションです。

- phase-7 までは、NeeView のソースコードを挙動の理解のための参照にのみ使用しました。
- phase-8 以降は、NeeView に近づけるため、一部のロジックと配色・画面構成を NeeView から移植しています。
  移植した範囲は下の「移植した箇所」に記載します。
- NeeView の名称・ロゴ・アイコンは使用していません。

### 移植した箇所

| YomiView | 移植元（NeeView） | 内容 |
|---|---|---|
| `YomiView/Views/Theme.swift` | `NeeView/Libraries/Themes/DarkTheme.json` | ダークテーマの配色 |
| `YomiView/Services/Bookshelf.swift` | `NeeView/SidePanels/Bookshelf/FolderList/FolderOrder.cs`、`FolderCollection.cs`、`FolderList.cs` | 本棚の並び順、フォルダを先に並べる規則、前後の本への移動 |
| `YomiView/Views/BookshelfPanelView.swift` | `NeeView/SidePanels/Bookshelf/FolderListView.xaml`、`FolderListBox.xaml.cs` | 本棚パネルの構成とクリック・ダブルクリックの動作 |
| `YomiView/Services/ThumbnailStore.swift`、`Views/FilmStripView.swift`、`Views/PageListPanelView.swift` | `NeeView/Config/ThumbnailConfig.cs`、`Config/FilmStripConfig.cs`、`PageSelect/FilmStrip`、`SidePanels/PageList` | サムネイルの大きさと保持数、フィルムストリップとページリストの構成 |
| `YomiView/Services/FileInformation.swift` | `NeeView/SidePanels/FileInfo/InformationKey.cs`、`InformationGroup.cs` | ファイル情報の項目とグループ |
| `YomiView/Services/CanvasLayout.swift` | `NeeView/PageFrames/ContentSizeCalcurator.cs`、`NeeView/Book/PageStretchMode.cs` | ストレッチの倍率の計算、拡大・縮小の許可、見開きの高さ揃え |
| `YomiView/Services/SpreadCalculator.swift`（最後のページを単独・横長ページの分割） | `NeeView/PageFrames/PageFrameFactory.cs`、`PageFrameContext.cs` | 最後のページを単独にする判定、1ページ表示のときだけ横長ページを分割する条件と読む順 |
| `YomiView/Services/PageSort.swift` | `NeeView/Book/PageSortMode.cs`、`NeeView/Book/BookPageSort.cs` | ページの並び順の種類と、同じ値のときに名前順で並べる規則 |
| `YomiView/Views/NavigatorPanelView.swift`、`ReaderView.swift` のマウス操作 | `NeeView/SidePanels/Navigate`、`NeeView/Config/ViewConfig.cs`、`MouseConfig.cs`、`LoupeConfig.cs` | ナビゲーターの構成、ドラッグ・長押しルーペ・カーソルを隠す動作と既定値 |
| 表示文言 | `NeeView/Languages/ja.restext` | 「本棚」「名前↑」「次のブックはありません」などの日本語表示 |
| `YomiView/Views/ReaderView.swift`、`AddressBarView.swift`、`SidePanelFrame.swift`、`PageSliderView.swift` | `NeeView/MainWindow/MainWindow.xaml`、`NeeView/AddressBar/AddressBarView.xaml`、`NeeView/PageSelect/PageSlider/PageSliderView.xaml` | 画面構成（アドレスバー、サイドパネル、ページスライダーの配置） |

NeeView: https://github.com/neelabo/NeeView

## 依存ライブラリ

| ライブラリ | ライセンス | 用途 |
|---|---|---|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | MIT License (Copyright (c) Thomas Zoechling) | ZIP / CBZ の読み込み |
