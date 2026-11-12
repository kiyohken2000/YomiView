<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="YomiView のアイコン">
</p>

# YomiView

macOS 向けの画像・漫画ビューアです。フォルダ、ZIP / CBZ、PDF を「本」として開き、見開き・右開きでページをめくって読めます。

Windows 向け画像ビューア [NeeView](https://github.com/neelabo/NeeView) の中核機能を参考に、Swift / SwiftUI で新たに実装しています（詳細は [NOTICE.md](NOTICE.md)）。

## ダウンロード

[Releases](https://github.com/kiyohken2000/YomiView/releases/latest) から `YomiView-<バージョン>.dmg` をダウンロードします。DMG を開き、`YomiView.app` を「アプリケーション」フォルダへドラッグしてください。

- macOS 14 以降に対応しています（Apple シリコン / Intel）。
- Developer ID で署名し、Apple の公証を受けているので、警告なしで起動できます。

## できること

- **開ける本**：画像の入ったフォルダ、ZIP / CBZ、PDF
  - 画像は PNG、JPEG、GIF、WebP、BMP、TIFF、HEIC に対応しています。
  - ページはファイル名の自然順（`page2` → `page10`）に並びます。
- **見開きと右開き**
  - ウィンドウを横長にすると自動で見開きになります。
  - 表紙や横長のページは単独で表示します。
  - 右開きと左開きを切り替えられます。
- **表示**
  - ウィンドウや幅・高さに合わせて表示できます。
  - 拡大・縮小、回転、反転ができます。
  - 長押しでルーペが使えます。
  - 背景色を変えられます。
- **移動**
  - キーボード、スクロール、ページスライダー、フィルムストリップでページを移動できます。
  - 同じフォルダにある前後の本を開けます。
- **パネル**：本棚、ページリスト、履歴、ブックマーク、ファイル情報（Exif を含む）、ナビゲーター
- **その他**
  - スライドショーで自動でページを送れます。
  - フルスクリーンでは、アドレスバーやパネルを自動で隠します。
  - ファイルをドラッグ＆ドロップして開けます。
  - 「最近開いた本」から開き直せます。

## 使い方

本は次のどれかの方法で開けます。

- ファイル ▸ 開く…（⌘O）を使う
- ウィンドウへドラッグ＆ドロップする
- アドレス欄にパスを入力して Enter を押す

### 主なキー操作

| 操作 | キー・操作 |
|---|---|
| 次のページ | ←（右開き）/ →（左開き）、↓、Space、下へスクロール |
| 前のページ | →（右開き）/ ←（左開き）、↑、Shift+Space、上へスクロール |
| 先頭 / 末尾 | Home / End（ノートの内蔵キーボードでは fn+← / fn+→） |
| 見開き / 1ページの切り替え | M |
| 右開き / 左開きの切り替え | D |
| フルスクリーン | F（⌃⌘F も使えます） |
| スライドショーの再生 / 停止 | F5 |
| ウィンドウに合わせる / オリジナル サイズ | ⌘9 / ⌘0 |
| 拡大 / 縮小 | ⌘+ / ⌘-、ピンチ |
| 右回転 / 左回転 | ⌘R / ⌘L |
| 次の本 / 前の本 | ⌥↓ / ⌥↑ |
| 本の履歴を戻る / 進む、上の階層へ | ⌘[ / ⌘]、⌘↑ |
| ブックマークに登録 / 削除 | ⌘D |
| パネルの開閉 | B 本棚、P ページリスト、H 履歴、I ファイル情報、N ナビゲーター、⌥⌘B ブックマーク |

### 設定（⌘,）

設定で変えられる主な項目は次のとおりです。

- **開き方向**：右開き / 左開き
- **見開き**
  - 表紙・最後のページ・横長のページを単独で表示するか
  - 1ページ表示のとき、横長のページを分割するか
- **ページ**
  - ページの並び順
  - サブフォルダーの画像も読み込むか
  - 前回開いたページから開くか（既定はオフ）
- **スライドショー**：ページを切り替える間隔、ループ再生するか
- **ウィンドウ**：フルスクリーンで自動非表示にするか

## 開発

### 必要なもの

- macOS 14 以降
- Xcode（Swift 5.9 以降）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

### ビルドとテスト

```sh
open YomiView.xcodeproj   # Xcode で開いて ⌘R
```

コマンドラインでテストする場合：

```sh
xcodebuild -project YomiView.xcodeproj -scheme YomiView -destination 'platform=macOS' test
```

プロジェクトファイルは `project.yml` から XcodeGen で作っています。ファイルの追加・削除やプロジェクト設定の変更は、`project.yml` を編集してから次を実行してください。

```sh
xcodegen generate
```

見た目はスナップショットテストでも確認できます。スキャン漫画などの本のパスを指定してください。

```sh
TEST_RUNNER_YOMIVIEW_SNAPSHOT_DIR=/tmp/yomiview-snap TEST_RUNNER_YOMIVIEW_SNAPSHOT_BOOK=/path/to/book \
  xcodebuild -project YomiView.xcodeproj -scheme YomiView -destination 'platform=macOS' test -only-testing:YomiViewTests/SnapshotTests
```

機能ごとの手動確認手順は [docs/manual-testing.md](docs/manual-testing.md) にあります。

### 配布用 DMG の作り方

Developer ID で署名し、Apple の公証を受けた DMG を `build/release/` に作ります。

事前の準備（一度だけ）：

1. Xcode ▸ 設定 ▸ Accounts で Apple Developer Program のアカウントを選び、Manage Certificates… ▸ ＋ ▸「Developer ID Application」で証明書を作ります。
2. [appleid.apple.com](https://appleid.apple.com) で App 用パスワードを作り、公証用の認証情報をキーチェーンに保存します。

```sh
xcrun notarytool store-credentials YomiView --apple-id <Apple ID> --team-id <チーム ID>
```

作成：

```sh
scripts/release.sh            # Release ビルド → 署名 → DMG → 公証 → ステープル
NOTARIZE=0 scripts/release.sh # 公証せずに、署名と DMG の作成だけ
```

- バージョンは `YomiView/Resources/Info.plist` の `CFBundleShortVersionString` で決まります。
- できた DMG は、GitHub Release に添付して公開します。

```sh
gh release create v<バージョン> build/release/YomiView-<バージョン>.dmg --title "YomiView <バージョン>" --notes "…"
```

## ライセンス

MIT License（[LICENSE](LICENSE)）。判断の記録は [DECISIONS.md](DECISIONS.md) を参照してください。
