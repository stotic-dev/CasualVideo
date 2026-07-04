# metadata

App Store Connect へ同期するメタ情報（リリースノート・スクリーンショット）を管理するディレクトリ。

Xcode Cloud の **Release ワークフロー**（`vN.N.N` タグ起動）で `ci_scripts/ci_post_xcodebuild.sh` が実行され、
[asc-metadata-cli](https://github.com/stotic-dev/asc-metadata-cli) がこのディレクトリの内容を
App Store Connect に同期する（新バージョン作成 + リリースノート + スクリーンショット）。

## ディレクトリ構造

```
metadata/
└── ja/
    ├── release_notes.txt          # このバージョンの What's New（空ならスキップ）
    └── screenshots/
        └── APP_IPHONE_67/         # displayType 単位。ファイル名昇順で並ぶ
            ├── 01_home.png
            └── 02_player.png
```

- ディレクトリ名は App Store Connect のロケール識別子（`ja`, `en-US` 等）に合わせる。
- `screenshots/` 配下は [screenshotDisplayType](https://developer.apple.com/documentation/appstoreconnectapi/screenshotdisplaytype)（`APP_IPHONE_67` 等）名のディレクトリにする。
- スクリーンショットの表示順はファイル名昇順（`01_`, `02_` の接頭辞で制御）。対応拡張子は png / jpg / jpeg。
- `release_notes.txt` と `screenshots/` はどちらか一方だけでもよい。

## リリース手順

1. このバージョンで公開する `release_notes.txt` / スクリーンショットを更新してコミットする。
2. `vN.N.N`（例: `v1.1.0`）のタグを打つ。
3. Xcode Cloud の Release ワークフローがタグ起動し、アーカイブ後に `ci_post_xcodebuild.sh` がメタ情報を同期する。
   - バージョン番号はタグ（`v` を除いた `N.N.N`）から読み取られる。

## 事前設定（Xcode Cloud の環境変数 / Secret）

Release ワークフローに以下の Secret を登録しておくこと（App Store Connect API キー・ロールは App Manager 以上）。

| 環境変数 | 内容 |
|---|---|
| `ASC_KEY_ID` | API キーの Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_PRIVATE_KEY` | `.p8` ファイルの中身（PEM 文字列） |

## 注意事項

- アプリの **初回バージョン** にはリリースノートを設定できない（App Store Connect の仕様）。
- 対象バージョンが編集不可の状態（審査中等）だとメタ情報更新は API エラーになる。
- スクリーンショットは displayType ディレクトリ単位で「全削除 → 再アップロード」される。
- 画像解像度が displayType の要求と一致しないと、アップロードは成功しても ASC 側検証で FAILED になる。
