# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

`CasualVideo` は SwiftUI 製の iOS アプリ。アプリ本体は薄いシェルで、ロジックはローカル Swift パッケージ `LocalPackage` に集約するレイヤードアーキテクチャを採用している（現状は雛形段階）。

- Swift 6（`swiftLanguageModes: [.v6]` / `swift-tools-version: 6.3`）
- Deployment Target: iOS 26.0（`LocalPackage` は `.iOS(.v26)` / `.macOS(.v26)` 対応）
- Bundle ID: `stotic-dev.CasualVideo`
- テストフレームワーク: Swift Testing（`import Testing` / `@Test` / `#expect`）。XCTest ではない。

## アーキテクチャ

Xcode プロジェクト `CasualVideo.xcodeproj` が `LocalPackage` をローカルパッケージとして参照する構成。

```
CasualVideo/              # アプリ本体（@main, SwiftUI エントリポイントのみ）
  CasualVideoApp.swift
  ContentView.swift
LocalPackage/             # 実装の中心。SPM パッケージ
  Sources/
    App/                  # App ターゲット（library product として公開される唯一のターゲット）
    Features/Main/        # Main ターゲット（path 指定: Sources/Features/Main）
    Core/                 # Core ターゲット（ドメイン/共通ロジック想定）
    Infra/                # Infra ターゲット（外部 I/O・永続化想定）
  Tests/
    MainTests/            # Main 用テスト
    CoreTests/            # Core 用テスト
```

### 依存関係

ターゲット間の依存方向は以下（App を頂点に、Core を共通基盤とする一方向の依存）:

```
App ──┬──> Main ──> Core
      ├──> Core
      └──> Infra
```

- `App`: `Main` / `Core` / `Infra` に依存。アプリへ公開する唯一の library product。依存の組み立て（assemble）を担う。
- `Main`（Features 層）: `Core` に依存。
- `Core`: 依存なし（最下層の共通ロジック）。
- `Infra`: 依存なし。

逆方向の依存（例: `Core` → `Main`）を作らないこと。

**各レイヤーの責務・DI 方針・状態管理（Store）の詳細は [docs/architecture.md](docs/architecture.md)、テスト方針は [docs/testing.md](docs/testing.md) を必ず参照すること。** 新規実装やレビュー時はこのルールに従う。

### Package.swift の編集方法

`Package.swift` はターゲットを `AppTarget` 構造体（ファイル末尾の `// MARK: - Targets`）で宣言的に定義している。直接 `.target(...)` の文字列を書き換えるのではなく、この仕組みに沿って編集する:

- **依存追加**: 該当 `AppTarget` の `dependencies:` に他の `AppTarget` インスタンス（`core` など）を渡す。`targetDependencies` が自動で `Target.Dependency` に変換する。
- **テストターゲット追加**: `AppTarget` の `testTargetName:` を指定し、`targets` 配列に `.testTarget(name: xxx.testTargetName!, dependencies: xxx.testDependencies)` を追加する。
- **新規ターゲット追加**: `AppTarget` インスタンスを定義し、`targets` 配列に `.target(name: xxx.name, dependencies: xxx.targetDependencies)` を追加。アプリへ公開する場合は `products` にも追加する（現状は `App` のみ）。

## よく使うコマンド

ビルド・テストは `LocalPackage` 単体（SPM）と、アプリ全体（xcodebuild）の2系統がある。ロジック開発は基本 SPM 側で完結させると速い。

### コード検証（Makefile / 推奨）

**コード実装後は必ず以下で検証すること。** リポジトリルートの `Makefile` に検証コマンドを集約している。

```bash
make build   # LocalPackage を iOS シミュレーター向けにビルド
make test    # LocalPackage のテストを実行（カバレッジ計測あり）
make verify  # build → test をまとめて実行（実装後の検証はこれを使う）
make help    # 利用可能なターゲット一覧を表示
```

`make build` / `make test` は iOS シミュレーター SDK（`arm64-apple-ios26.2-simulator`）を指定して実行するため、実機向けの整合性を保ったまま検証できる。

### Swift Package（推奨: ロジック開発時）

```bash
cd LocalPackage
swift build                          # 全ターゲットビルド
swift test                           # 全テスト実行
swift test --filter CoreTests        # 特定テストターゲット
swift test --filter CoreTests.example  # 単一テスト（型名.関数名 ではなく test 名で絞る）
```

### Xcode プロジェクト（アプリ全体 / シミュレータ）

利用可能なスキーム: `CasualVideo`（アプリ）, `App`, `CoreTests`, `MainTests`

```bash
# アプリのビルド
xcodebuild -scheme CasualVideo -destination 'platform=iOS Simulator,name=iPhone 16' build

# テスト
xcodebuild -scheme CoreTests -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## 注意点

- `Sources/Core/File.swift` 等の `File.swift` および `MyLibrary.swift` はスキャフォールド生成の空ファイル。実装追加時は意味のあるファイル名へリネームする。
- iOS 26.0 / Swift 6.3 と Xcode のバージョン整合が必要（このリポジトリは Xcode 26.x 前提）。
