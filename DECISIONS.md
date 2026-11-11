# DECISIONS

実装中に行った判断の記録。計画書（docs/NEEVIEW_MAC_PLAN.md）に書かれていない事項や、未決事項の扱いをここに残す。

## 未決事項（計画書 9章）への対応

計画書に書かれたデフォルト方針で進める。

| # | 未決事項 | 採用した方針 |
|---|---|---|
| 1 | 対象のmacOSバージョン | macOS 14.0 以降（deployment target 14.0） |
| 2 | RAR / 7z 対応 | MVPに含めない。対応形式はフォルダ / ZIP / CBZ / PDF のみ |
| 3 | キーボード割り当て | 計画書 5.4 の表をそのまま初期値とする。表にない操作（ファイルを開く等）は macOS の慣習（⌘O など）に合わせる |
| 4 | 配布方法 | 個人利用を前提とする。ソースは MIT で GitHub 公開できる状態を保つが、バイナリ配布・公証・App Store 配布は行わない |
| 5 | アプリ名 | `YomiView` で進める。正式公開前に名称衝突の確認が必要（未確認） |

## Phase 0

- **Xcodeプロジェクトの作成方法**：XcodeGen（2.46.0, Homebrew で導入）を使用。`project.yml` を正とし、生成した `YomiView.xcodeproj` もコミットする（XcodeGen がなくても Xcode で開けるように）。プロジェクト構成を変えるときは `project.yml` を編集して `xcodegen generate` を再実行する。
- **ZIPFoundation**：SPM で `from: 0.9.19` を指定（解決されたバージョンは 0.9.20）。
- **Swift の言語モード**：Swift 5 モード（`SWIFT_VERSION = 5.0`）。計画書の「Swift 5.9 以降」に合わせ、Swift 6 の strict concurrency による非本質的な修正を避けるため。コンパイラ自体は Xcode 付属のもの。
- **App Sandbox**：無効。任意のフォルダや外付けドライブ上のファイルをパスで開き、最近開いた本をパスで UserDefaults に保存する（5.6）ため。Sandbox を有効にする場合はセキュリティスコープ付きブックマークが必要になる。
- **署名**：ローカル実行用のアドホック署名（`CODE_SIGN_IDENTITY = "-"`）。Hardened Runtime は無効（公証しないため）。
- **Bundle ID**：`app.yomiview.YomiView`（仮）。
- **テストの配置**：計画書のツリーに合わせて `YomiView/Tests/` に置き、アプリターゲットからは除外してテストターゲット `YomiViewTests` に含める。
- **アーキテクチャ**：Xcode 標準設定（Debug はビルド中のマシンのアーキテクチャのみ、Release は arm64 + x86_64 のユニバーサル）。
- **ウィンドウ初期サイズ**：900×1100（縦長の漫画ページを想定）。背景は黒（画像ビューアの慣習）。
