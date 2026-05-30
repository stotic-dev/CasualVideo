# テスト方針

CasualVideo のテスト方針を定義する。実装・レビュー時はこのルールに従うこと。モジュール構成・依存ルールは [architecture.md](architecture.md) を参照。

## 基本方針

- テストは **SPM 側（`LocalPackage`）** で実装する。Xcode アプリ全体ではなく、ロジックを集約した `LocalPackage` を対象とすることで高速に回す。
- テストフレームワークは **Swift Testing**（`import Testing` / `@Test` / `#expect`）を用いる。XCTest は使わない。
- `ApplicationTarget`（`CasualVideo`）はテスタビリティ確保のため処理を最小化しており、テスト対象としない。ロジックは `App` 以下のモジュールへ寄せてテストする。

## テスト対象

- `Core` のドメインモデル
- `Core` の UseCase（複数 Feature のプレゼンテーションロジックで重複する部分のファサード）
- `Features` 内のドメインモデル

## テストの書き方

- テストターゲットは対象モジュールごとに分ける（`CoreTests` / `MainTests` など）。新規テストターゲットの追加は [architecture.md](architecture.md) の Package.swift 編集方法に従う。
- `Repository` は struct（振る舞いをクロージャで保持）で定義されているため、テストでは本番の `Impl` ではなくクロージャを差し替えたインスタンスを注入してテストする。protocol のモック型は作らない。

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

## 実行コマンド

```bash
cd LocalPackage
swift test                              # 全テスト実行
swift test --filter CoreTests           # 特定テストターゲット
swift test --filter CoreTests.example   # 単一テスト（test 名で絞る）
```
