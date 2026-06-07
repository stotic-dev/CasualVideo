---
name: implement-test
description: CasualVideo のテスト方針に則って Swift Testing でテストを実装するときに使う。Core のドメインモデル・UseCase、Features 内のドメインモデルに対するテストの追加・修正依頼で自動的に発火する。実装は test-implementer エージェント内で行う。
context: fork
agent: test-implementer
---

以下のテスト実装依頼を、CasualVideo のテスト方針に則って実装せよ。

## 依頼内容

$ARGUMENTS

## 実装手順

ルールの正本は `docs-internal/testing.md`。**着手前に必ず Read で読むこと。**

### 1. 対象がテスト対象かを確認する

テストするのは以下に限る。それ以外（特に ApplicationTarget や View の見た目）は対象外。

- `Core` のドメインモデル
- `Core` の UseCase（複数 Feature のプレゼンテーションロジックの重複ファサード）
- `Features` 内のドメインモデル

### 2. テストターゲットを選ぶ / 用意する

- 対象モジュールに対応するテストターゲットへ追加する（`Core` → `CoreTests`、`Main` → `MainTests`）。
- 新しいテストターゲットが必要なら、`Package.swift` の `AppTarget` に `testTargetName:` を指定し `.testTarget(...)` を追加する（`docs-internal/architecture.md` の Package.swift 編集方法に従う）。
- スキャフォールドの `MyLibraryTests.swift` / `example` テストは意味のある名前へリネームして使う。

### 3. Swift Testing で書く

- `import Testing` / `@Test` / `#expect`（または `#require`）を使う。**XCTest は使わない。**
- `@testable import <Module>` で対象モジュールを取り込む。

### 4. 依存は struct のクロージャ差し替えで stub する

`Repository` は protocol ではなく struct（クロージャ保持）。protocol モックは作らず、クロージャを差し替えたインスタンスを注入する。

```swift
import Testing
@testable import Core

@Test func loadCurrentUser() async throws {
    let stub = UserRepository(fetch: { _ in User(id: "1", name: "test") })
    let store = await SessionStore(userRepository: stub)
    try await store.load(id: "1")
    #expect(await store.currentUser?.name == "test")
}
```

`@MainActor` な Store などはアクター隔離・`await` に注意する。

## 完了前に必ず行うこと

- テスト対象が方針の範囲内か（ApplicationTarget や View 表示をテストしていないか）を確認する。
- Swift Testing で書き、stub を struct のクロージャ差し替えで作ったか確認する。
- **コード検証**: リポジトリルートで `make test` を実行し、テストが通ることを確認する（検証コマンドの正本は `Makefile` / `code-verification` スキル）。`make` コマンドは実行許可済みなので確認を求めず実行してよい。失敗したら原因を解消し、通る状態にしてから完了とする。
- 追加・修正したテストと、何を検証しているかを簡潔に報告する。
- **プロダクトコード（機能）の実装はこのスキルの責務外。** 必要なら `implement-feature` に委ねる旨を報告する。
