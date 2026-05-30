---
name: implement-feature
description: CasualVideo のレイヤードアーキテクチャに則って機能を実装するときに使う。新しい画面・ビジネスロジック・Repository・Store・依存追加など、LocalPackage への実装依頼で自動的に発火する。実装は feature-implementer エージェント内で行う。
context: fork
agent: feature-implementer
---

以下の実装依頼を、CasualVideo のアーキテクチャに則って実装せよ。

## 依頼内容

$ARGUMENTS

## 実装手順

ルールの正本は `docs/architecture.md`。**着手前に必ず Read で読むこと。**

### 1. 配置するレイヤーを決める

- 画面（View）と Feature 固有ロジック → `LocalPackage/Sources/Features/<Feature>`
- モジュール横断の定義（`Repository` の型定義・ドメインモデル・UseCase・Store）→ `Sources/Core`
- プロセス外依存（リモート/ローカルのデータソース）と直接やりとりするオブジェクト → `Sources/Infra`
- 依存の assemble、`Repository` の `Impl`（本番インスタンス）構築、DI の組み立て → `Sources/App`
- アプリのエントリポイント・`AppDelegate` 設定のみ → `CasualVideo`（ApplicationTarget）。**ロジックを置かない。**

### 2. 依存方向を守る

```
ApplicationTarget ──> App ──┬──> Features/<Feature> ──> Core
                            ├──> Infra ──────────────> Core
                            └──> Core
```

逆方向の依存・Feature 間依存・`Features` から `Infra` 直参照を作らない。`Features` は `Core` の `Repository`（struct）経由でアクセスし、その `Impl` は `App` が `Infra` を使って構築する。

### 3. 抽象化は protocol ではなく struct

`Repository` など差し替えが必要なものは **struct + クロージャプロパティ** で定義（protocol は原則使わない）。型定義は `Core`、本番実装（`.live(...)`）は `App`。

```swift
// Core: 型定義
struct UserRepository {
    var fetch: (User.ID) async throws -> User
}
// App: Infra を使って Impl を構築
extension UserRepository {
    static func live(client: APIClient) -> UserRepository {
        UserRepository(fetch: { id in try await client.getUser(id) })
    }
}
```

### 4. DI は EnvironmentValues 経由

`Repository` / UseCase は `EnvironmentValues`（`@Entry`）に登録し、`App` で `.environment(\.xxx, .live(...))` 注入、View では `@Environment(\.xxx)` で取得。

### 5. 共有状態が必要なら Store

アプリ全体で状態をキャッシュ・同期したい場合のみ Store を使う。Store は `@Observable` + `@MainActor` の `final class`。状態は `private` / `private(set)` でカプセル化し、公開 API 経由でのみ更新・共有。DI は型ベース（`@Environment(SessionStore.self)`）。

### 6. Package.swift を編集する場合

直接 `.target(...)` を書き換えず、`AppTarget` 構造体（ファイル末尾 `// MARK: - Targets`）の仕組みに沿う。依存追加は `dependencies:` に `AppTarget` インスタンスを渡す。新規ターゲット/テストターゲットの追加も同構造に従う。

### 7. スキャフォールドの空ファイル

`Sources/<Module>/File.swift` や `MyLibrary.swift` は空の雛形。実装追加時は意味のあるファイル名へリネームする。

## 完了前に必ず行うこと

- 配置レイヤー・依存方向・struct 抽象化・Environment DI の各ルール違反がないか自己チェックする。
- **コード検証**: リポジトリルートで `make build` を実行し、ビルドが通ることを確認する（検証コマンドの正本は `Makefile` / `code-verification` スキル）。`make` コマンドは実行許可済みなので確認を求めず実行してよい。失敗したら原因を解消し、通る状態にしてから完了とする。
- 変更したファイルと、どのレイヤーに何を置き依存方向を守った根拠を簡潔に報告する。
- **テストの実装はこのスキルの責務外。** 必要なら `implement-test` に委ねる旨を報告する。
