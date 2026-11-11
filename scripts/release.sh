#!/bin/zsh
# YomiView の配布用 DMG を作る：Release ビルド → Developer ID で署名 → DMG → 公証 → ステープル。
#
# 事前の準備（一度だけ）：
#   1. Xcode ▸ 設定 ▸ Accounts ▸ Manage Certificates で「Developer ID Application」証明書を作る
#   2. 公証用の認証情報をキーチェーンに保存する（App 用パスワードは appleid.apple.com で作る）
#        xcrun notarytool store-credentials YomiView --apple-id <Apple ID> --team-id <チーム ID>
#
# 使い方： scripts/release.sh            （公証まで行う）
#          NOTARIZE=0 scripts/release.sh （署名と DMG の作成だけ）
set -euo pipefail

cd "$(dirname "$0")/.."
PROFILE="${NOTARY_PROFILE:-YomiView}"
NOTARIZE="${NOTARIZE:-1}"
OUT=build/release
DERIVED=build/DerivedData-release

IDENTITY_LINE=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 || true)
if [[ -z "$IDENTITY_LINE" ]]; then
  echo "Developer ID Application の証明書が見つかりません（スクリプト冒頭の準備 1 を参照）" >&2
  exit 1
fi
IDENTITY=$(echo "$IDENTITY_LINE" | sed -E 's/.*"(.*)"/\1/')
TEAM=$(echo "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" YomiView/Resources/Info.plist)
echo "署名: $IDENTITY / バージョン: $VERSION"

rm -rf "$OUT" "$DERIVED"
mkdir -p "$OUT"

xcodegen generate -q
xcodebuild -project YomiView.xcodeproj -scheme YomiView -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build | grep -E "error:|warning:|BUILD" || true

APP="$DERIVED/Build/Products/Release/YomiView.app"
[[ -d "$APP" ]] || { echo "ビルドに失敗しました" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -q "runtime" || { echo "Hardened Runtime が有効になっていません" >&2; exit 1; }

# DMG：アプリと「アプリケーション」フォルダへのリンクを並べる
STAGE="$OUT/stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/YomiView.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/YomiView-$VERSION.dmg"
hdiutil create -volname "YomiView $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ "$NOTARIZE" == "1" ]]; then
  echo "公証に提出しています（数分かかります）…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl -a -vv -t open --context context:primary-signature "$DMG"
fi

shasum -a 256 "$DMG"
echo "できました: $DMG"
