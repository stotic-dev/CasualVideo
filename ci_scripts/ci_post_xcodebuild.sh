#!/bin/sh

#
# ci_post_xcodebuild.sh
#
# Xcode Cloud の xcodebuild アクション完了後に実行されるフック。
# PreRelease ワークフローのときに、リポジトリ内の metadata/ を元に
# App Store Connect へ以下を同期する。
#
#   - 新バージョンの作成（既に存在すれば再利用）
#   - リリースノート（What's New）のロケール別更新
#   - スクリーンショットの追加・更新
#
# 同期処理は https://github.com/stotic-dev/asc-metadata-cli を使用する。
#
# 【前提: Xcode Cloud の環境変数（Secret）に以下を登録しておくこと】
#   ASC_KEY_ID       … App Store Connect API キーの Key ID
#   ASC_ISSUER_ID    … Issuer ID
#   ASC_PRIVATE_KEY  … .p8 ファイルの中身（PEM 文字列）
#

set -eu

# --- 実行条件の判定 -------------------------------------------------------

# PreRelease ワークフロー以外ではスキップ（テスト/開発ワークフロー等）
if [ "${CI_WORKFLOW:-}" != "PreRelease" ]; then
    echo "[asc-metadata] CI_WORKFLOW='${CI_WORKFLOW:-}' is not 'PreRelease'. Skip metadata sync."
    exit 0
fi

# archive アクション完了後のみ実行（同一ワークフロー内での多重実行を避ける）
if [ -z "${CI_ARCHIVE_PATH:-}" ]; then
    echo "[asc-metadata] No CI_ARCHIVE_PATH (not an archive result). Skip metadata sync."
    exit 0
fi

# --- アーカイブ済みアプリの Info.plist からバージョンを読み取る -----------
#
# ソースの Info.plist は GENERATE_INFOPLIST_FILE=YES によりバージョンを
# 持たない（MARKETING_VERSION から生成される）ため、アーカイブされた
# .app の Info.plist から CFBundleShortVersionString を読む。

APP_PATH=$(ls -d "$CI_ARCHIVE_PATH"/Products/Applications/*.app 2>/dev/null | head -n 1)
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "[asc-metadata] Archived .app not found under $CI_ARCHIVE_PATH/Products/Applications. Abort." >&2
    exit 1
fi

APP_INFO_PLIST="$APP_PATH/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_INFO_PLIST")
if [ -z "$VERSION" ]; then
    echo "[asc-metadata] Failed to read CFBundleShortVersionString from $APP_INFO_PLIST. Abort." >&2
    exit 1
fi

echo "[asc-metadata] App='$APP_PATH' Version='$VERSION'"

# --- 各種パス -------------------------------------------------------------

BUNDLE_ID="stotic-dev.CasualVideo"
REPO_PATH="${CI_PRIMARY_REPOSITORY_PATH:-$PWD}"
METADATA_DIR="$REPO_PATH/metadata"
PLUGIN_DIR="$REPO_PATH/ci_scripts/asc-metadata-plugin"

if [ ! -d "$METADATA_DIR" ]; then
    echo "[asc-metadata] metadata directory not found: $METADATA_DIR. Abort." >&2
    exit 1
fi

# --- asc-metadata-cli を実行 ----------------------------------------------
#
# ci_scripts/asc-metadata-plugin は asc-metadata-cli を binaryTarget
# (artifactbundle) として取り込み、command plugin 経由で実行する。
# プレビルドバイナリのため SDK のフルコンパイルが不要で CI が速い。
#
#   --disable-sandbox            : ネットワーク・環境変数アクセスのため sandbox を無効化
#   --allow-network-connections  : App Store Connect API への通信を許可（非対話で承認）

echo "[asc-metadata] Running sync (bundle-id=$BUNDLE_ID version=$VERSION)"
swift package \
    --package-path "$PLUGIN_DIR" \
    --disable-sandbox \
    --allow-network-connections all \
    asc-metadata-sync \
    sync \
    --bundle-id "$BUNDLE_ID" \
    --version "$VERSION" \
    --metadata-dir "$METADATA_DIR"

echo "[asc-metadata] Done."
