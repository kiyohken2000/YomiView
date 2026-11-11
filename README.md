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
2. 黒い空のウィンドウが表示され、中央に「フォルダ、ZIP、CBZ を開いてください」と「開く…」ボタンが出ることを確認する

### Phase 1：フォルダと ZIP / CBZ の閲覧（1ページ表示）

準備：ファイル名に数字を含む画像（例：`page1.png`, `page2.png`, `page10.png`, `page11.png`）を入れたフォルダを用意し、
Finder でそのフォルダを右クリック →「圧縮」して ZIP も作る。CBZ は ZIP の拡張子を `.cbz` に変えたものでよい。

1. ファイル ▸ 開く…（⌘O）でダイアログが開くことを確認する。ウィンドウ中央の「開く…」ボタンでも同じダイアログが開く
2. フォルダを選んで開き、1ページ目（`page1`）が表示され、ウィンドウタイトルが `フォルダ名 (1 / 4)` になることを確認する
3. → キーで `page1 → page2 → page10 → page11` の順（自然順）に進むことを確認する
4. 最後のページで → を押しても何も起きない（タイトルが `(4 / 4)` のまま）ことを確認する
5. ← キーで戻れること、1ページ目で ← を押しても何も起きないことを確認する
6. 同じ手順を ZIP と CBZ でも行う。Finder で作った ZIP に含まれる `__MACOSX` フォルダの画像がページに出ないことを確認する
7. 画像がウィンドウに合わせて縦横比を保ったまま表示され、ウィンドウサイズを変えると追従することを確認する
8. テキストファイルなど対応していないファイルを開こうとしたとき（ダイアログで選べない場合は、画像のないフォルダを選ぶ）、
   「本を開けません」のアラートが表示されアプリが落ちないことを確認する
9. 中身が画像でない `.png`（テキストファイルの拡張子を変えたもの）を含むフォルダを開き、そのページだけ「読み込めません」と表示され、
   前後のページには移動できることを確認する
10. 日本語のファイル名を含む ZIP（Windows で作られたもの）を開き、ページの順番が正しいことを確認する（任意）

## ライセンス

MIT License（[LICENSE](LICENSE)）。判断の記録は [DECISIONS.md](DECISIONS.md) を参照。
