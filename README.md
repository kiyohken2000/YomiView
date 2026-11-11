# YomiView

macOS 向けの画像・漫画ビューア。フォルダや ZIP / CBZ を「本」として開き、ページ単位で閲覧します。

Windows 向け画像ビューア [NeeView](https://github.com/neelabo/NeeView) の中核機能を参考に、Swift / SwiftUI で新たに実装しています（詳細は [NOTICE.md](NOTICE.md)）。

## 動作環境

- macOS 14 以降
- Xcode（Swift 5.9 以降）

## ビルド

```sh
open YomiView.xcodeproj   # Xcode で開いて ⌘R
```

コマンドラインでビルド・テストする場合：

```sh
xcodebuild -project YomiView.xcodeproj -scheme YomiView -destination 'platform=macOS' test
```

プロジェクトファイルは [XcodeGen](https://github.com/yonaskolb/XcodeGen) で `project.yml` から生成しています。ファイルを追加・削除した場合やプロジェクト設定を変える場合は、`project.yml` を編集してから次を実行してください。

```sh
brew install xcodegen
xcodegen generate
```

## 手動確認手順

### Phase 0：起動

1. Xcode で `YomiView.xcodeproj` を開き、⌘R で実行する
2. 黒い空のウィンドウが表示されることを確認する

## ライセンス

MIT License（[LICENSE](LICENSE)）。判断の記録は [DECISIONS.md](DECISIONS.md) を参照。
