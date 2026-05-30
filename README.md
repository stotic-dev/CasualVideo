# CasualVideo

iOS の写真ライブラリ（標準アルバム / iCloud）にある動画を、アプリから **ラフに流し見** するための個人用動画プレイヤー。マルチタスクしながら思い出を振り返る体験を中心に据えた SwiftUI 製アプリです。

一言で言えば「**自分専用の、アルバム動画版の"ながら見"プレイヤー**」。

> 本プロジェクトは現在 **雛形段階** です。本 README は要件・設計ドキュメントを基にした初期版であり、開発の進行に応じて更新します。

## コンセプト

- **ターゲット**: 開発者本人（単一ユーザー）。不特定多数への配信・共有は想定せず、アカウント / ログイン機構は不要。
- **体験のキーワード**:
  - **ラフ** — 厳密な操作より「とりあえず流す」を優先する
  - **ながら見 / マルチタスク** — 他アプリを操作しながら動画を流し続けられる（PIP）
  - **振り返り** — 過去の動画を連続・シャッフルで眺める

## 主な機能（MVP）

最優先体験は **PIP バックグラウンド再生**。これを軸に以下を MVP の範囲とします。

| # | 機能 | 概要 |
| --- | --- | --- |
| F-1 | 写真ライブラリの動画一覧 | PhotoKit 経由でアルバム / iCloud の動画を一覧表示 |
| F-2 | 動画再生 | 一覧から選んだ動画を再生 |
| F-3 | **PIP バックグラウンド再生** | Picture in Picture で、他アプリ操作中・バックグラウンドでも再生を継続（**MVP の中核**） |
| F-4 | プレイリスト連続再生 | 複数動画を途切れず連続再生 |
| F-5 | シャッフル / リピート | プレイリストのシャッフル・リピート再生 |
| F-6 | プレイリスト編成 | 手動選択 / 既存アルバム単位 / 全動画 の3通りで編成 |
| F-7 | 音声ミュート切り替え | 再生中に音声のミュート / 音ありをトグル切り替え |
| F-8 | プレイリストの永続化 | 作成したプレイリスト・設定を端末内に保存（SwiftData） |

### 将来拡張（MVP 対象外）

- 期間・日付による自動プレイリスト生成（「先月」「去年の今頃」など）
- iCloud によるプレイリストのマルチデバイス同期
- 再生速度の変更、フィルター・編集などの加工機能
- お気に入り / タグ付け、検索

### 非対象（スコープ外）

- 動画の撮影・編集・書き出し
- SNS 共有・外部送信
- 複数ユーザー / アカウント管理

## 技術スタック

- **言語**: Swift 6（Swift Language Mode v6 / swift-tools-version 6.3）
- **UI**: SwiftUI
- **最低対応 OS**: iOS 26.0（iPhone 対象）
- **写真ライブラリ**: PhotoKit（`PHAsset` / `PHImageManager` / `PHCachingImageManager`）。iCloud 動画は `PHVideoRequestOptions` でネットワークアクセス許可
- **再生エンジン**: AVKit / AVFoundation（`AVPlayer` / `AVPlayerLayer` / `AVPictureInPictureController`）
- **バックグラウンド再生**: `AVAudioSession` のカテゴリ設定、Background Modes（Audio / AirPlay / PiP）
- **永続化**: SwiftData（端末内）。プレイリストは動画の識別子（`localIdentifier`）参照で保持
- **アーキテクチャ**: レイヤードアーキテクチャ（App / Features / Core / Infra）
- **テスト**: Swift Testing（`import Testing` / `@Test` / `#expect`）
- **Bundle ID**: `stotic-dev.CasualVideo`
- **前提**: Xcode 26.x

## プロジェクト構成

アプリ本体は薄いシェルとし、ロジックはローカル Swift パッケージ `LocalPackage` に集約します。

```
CasualVideo/              # アプリ本体（@main, SwiftUI エントリポイントのみ）
  CasualVideoApp.swift
  ContentView.swift
LocalPackage/             # 実装の中心。SPM パッケージ
  Sources/
    App/                  # App ターゲット（依存を assemble。公開する唯一の library product）
    Features/Main/        # Main ターゲット（画面 + Feature 固有ロジック）
    Core/                 # Core ターゲット（ドメイン / UseCase / Repository 型定義）
    Infra/                # Infra ターゲット（プロセス外依存との唯一の窓口）
  Tests/
    MainTests/            # Main 用テスト
    CoreTests/            # Core 用テスト
docs/                     # 設計ドキュメント
```

## アーキテクチャ

App を頂点とした一方向の依存で構成されるレイヤードアーキテクチャを採用しています。

```
ApplicationTarget ──> App ──┬──> Features/<Feature> ──> Core
                            ├──> Infra ──────────────> Core
                            └──> Core
```

| レイヤー | 責務 |
| --- | --- |
| **ApplicationTarget（CasualVideo）** | エントリポイントと起動時設定。テスタビリティ確保のため処理は最小限に留める |
| **App** | すべての依存を **assemble（組み立て）** するモジュール。`Infra` を参照して `Repository` の `Impl` を実装し DI する |
| **Features/\<Feature\>** | 画面（View）と Feature 固有のビジネスロジック。横断的な定義は持たず `Core` を参照 |
| **Core** | モジュール横断の定義（`Repository` 型定義 / ドメインモデル / UseCase）。最下層・依存なし |
| **Infra** | プロセス外依存（PhotoKit / SwiftData など）との唯一の窓口。single source of truth を管理 |

### 依存と設計のルール

- 依存は上記の一方向のみ。逆方向の依存（例: `Core` → `Features`）は作らない
- `Features` 同士は原則依存させない。共有が必要な定義は `Core` に上げる
- `App` のみが `Infra` を参照できる。`Features` から `Infra` を直接参照せず、`Repository` 経由でアクセスする
- **抽象化は protocol ではなく struct**: `Repository` は振る舞いをクロージャで保持する struct で定義（型定義は `Core`、本番実装 `Impl` は `App` で組み立て）
- **DI は SwiftUI の `EnvironmentValues` 経由**: View 側は `@Environment` で取り出して利用
- **状態管理（Store）**: `@Observable` + `@MainActor` な `final class`。状態はカプセル化し、公開 API 経由でのみ共有・更新。Store もオブジェクト型ベースの `.environment(_:)` / `@Environment(_:)` で DI

詳細は [docs/architecture.md](docs/architecture.md) を参照してください。

## 画面構成（たたき台）

- **ライブラリ画面**: 写真ライブラリの動画一覧 / アルバム一覧。再生・プレイリスト追加の起点
- **プレイリスト一覧画面**: 作成済みプレイリストの一覧と管理
- **プレイリスト詳細画面**: 内包する動画一覧と再生開始（連続 / シャッフル / リピート）
- **再生画面**: 全画面再生。PIP 起動、ミュート切り替え、次/前送り、再生モード切り替え

## 開発

ビルド・テストは `LocalPackage` 単体（SPM）と、アプリ全体（xcodebuild）の2系統があります。ロジック開発は基本 SPM 側で完結させると高速です。

### Swift Package（推奨: ロジック開発時）

```bash
cd LocalPackage
swift build                            # 全ターゲットビルド
swift test                             # 全テスト実行
swift test --filter CoreTests          # 特定テストターゲット
swift test --filter CoreTests.example  # 単一テスト（test 名で絞る）
```

### Xcode プロジェクト（アプリ全体 / シミュレータ）

利用可能なスキーム: `CasualVideo`（アプリ）, `App`, `CoreTests`, `MainTests`

```bash
# アプリのビルド
xcodebuild -scheme CasualVideo -destination 'platform=iOS Simulator,name=iPhone 16' build

# テスト
xcodebuild -scheme CoreTests -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## テスト

- テストは **SPM 側（`LocalPackage`）** で実装し、高速に回す
- フレームワークは **Swift Testing**（XCTest は使わない）
- テスト対象: `Core` のドメインモデル / UseCase、`Features` 内のドメインモデル
- `Repository` は struct（振る舞いをクロージャで保持）のため、テストではクロージャを差し替えたインスタンスを注入する。protocol のモック型は作らない

詳細は [docs/testing.md](docs/testing.md) を参照してください。

## プライバシー

- 写真ライブラリアクセスの用途を `Info.plist`（`NSPhotoLibraryUsageDescription` 等）に明記する
- データは端末内に留め、外部送信しない

## ドキュメント

- [docs/requirements.md](docs/requirements.md) — 要件定義書
- [docs/architecture.md](docs/architecture.md) — アーキテクチャルール
- [docs/testing.md](docs/testing.md) — テスト方針
- [CLAUDE.md](CLAUDE.md) — Claude Code 向けの開発ガイド
