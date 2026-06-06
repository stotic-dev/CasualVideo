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

## プレゼンテーションロジック（Store）のテスト

Store のテストは状態遷移と副作用が絡み複雑になりやすい。可読性と回帰検知力を保つため、以下を**原則**とする。

### 1. AAA パターンをコメントで明示する

AAA（Arrange / Act / Assert）に倣ったとしても、複雑なテストではどこがどのフェーズか見逃しやすい。そのため**各ケースにフェーズ境界をコメントで明示する**こと。

- `// Arrange`（準備）/ `// Act`（実行）/ `// Assert`（検証）を必ず置く。
- 1 ケース内で複数回 Act → Assert する場合は `// Act` / `// Assert`（または `// Act & Assert`）を都度置き、フェーズの繰り返しが追えるようにする。

### 2. 公開状態を一括検証する共通 Assertion を用意する

ある操作の副作用として「関連する状態」だけを検証していると、実装変更で**意図しない別の状態が書き換わっても気付けない**。これを防ぐため、**Store の公開状態すべてを検証する共通 Assertion ヘルパー**を用意し、原則すべてのケースをこのヘルパーで検証する。

- 期待値は「公開状態すべて」を持つ `ExpectedState` 構造体で表現し、既定値を初期状態に合わせておく（各ケースは差分のみ上書きする）。
- ヘルパーには `sourceLocation: SourceLocation = #_sourceLocation` を渡し、失敗箇所が**呼び出し側の行**を指すようにする。
- 共通 Assertion は「Store 自身の状態」を対象とする。注入した Proxy / クロージャ（Mock）の呼び出し検証は副作用に応じて**ケースごとに別途**行う。

```swift
private struct ExpectedState {
    var isPlaying: Bool = false
    var currentIndex: Int?
    // …公開状態をすべて列挙し、既定値は初期状態に揃える
}

/// 公開状態すべてを毎回検証し、意図しない状態変化を検知する。
private func assertState(
    _ store: SomeStore,
    _ expected: ExpectedState,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(store.isPlaying == expected.isPlaying, sourceLocation: sourceLocation)
    #expect(store.currentIndex == expected.currentIndex, sourceLocation: sourceLocation)
    // …公開状態をすべて検証
}

@Test func playNext_advances() async {
    // Arrange
    let played = Box<[String]>([])
    let store = SomeStore(playerProxy: recordingProxy(played: played))
    await store.start(playlist: assets, from: 0)

    // Act
    await store.playNext()

    // Assert（公開状態は共通 Assertion でまとめて検証）
    assertState(store, ExpectedState(isPlaying: true, currentIndex: 1))
    // 副作用（Mock）はケース固有に検証
    #expect(played.value == ["a", "b"])
}
```

## 実行コマンド

```bash
cd LocalPackage
swift test                              # 全テスト実行
swift test --filter CoreTests           # 特定テストターゲット
swift test --filter CoreTests.example   # 単一テスト（test 名で絞る）
```
