# アーキテクチャルール

CasualVideo のモジュール構成と各レイヤーの責務・依存ルールを定義する。実装・レビュー時はこのルールに従うこと。

## モジュール構成

```
ApplicationTarget (CasualVideo)   # Xcode アプリターゲット
└── App                           # LocalPackage の library product（依存の組み立て）
    ├── Features/<Feature>        # 画面 + Feature 固有ロジック
    ├── Core                      # モジュール横断の定義（インターフェース・ドメイン・UseCase）
    └── Infra                     # プロセス外依存との唯一の窓口
```

## 依存方向

```
ApplicationTarget ──> App ──┬──> Features/<Feature> ──> Core
                            ├──> Infra ──────────────> Core
                            └──> Core
```

- 依存は上記の一方向のみ。逆方向の依存（例: `Core` → `Features`、`Core` → `Infra`）を作らない。
- `Features` 同士は原則依存させない。共有が必要な定義は `Core` に上げる。
- `App` のみが `Infra` を参照できる。`Features` から `Infra` を直接参照しない（後述の Repository インターフェース経由でアクセスする）。

## 各レイヤーの責務

### ApplicationTarget（CasualVideo）

- アプリのエントリーポイントと、`AppDelegate` で行う設定（起動時設定など）を責務とする。
- テストは SPM 側（`LocalPackage`）で行う。**テスタビリティ確保のため、ApplicationTarget に置く処理は原則最小限に留める。** ロジックは `App` 以下のモジュールへ寄せる。

### App

- すべての依存を **assemble（組み立て）** するモジュール。
- `Repository` などの依存を `Impl` オブジェクトとして実装し、`Environment` に DI する。
- `Infra` モジュールへの参照を持ち、それを用いて `Repository` の `Impl` を実装する。

### Features/\<Feature\>

- Feature の粒度でモジュールを切り分ける。
- 画面（View）と、その Feature 特有のビジネスロジックを含む。
- 横断的に使う定義（他 Feature や App と共有するもの）は持たず、`Core` を参照する。

### Core

- モジュール間をまたぐ定義を含む。
- 例: `Repository` の型定義（`App` でも `Features` でも参照するため `Core` に置く）。後述の通り protocol ではなく **struct** で定義する。
- ドメインモデル、および UseCase（複数 Feature のプレゼンテーションロジックで重複する部分のファサード）を含む。

### Infra

- リモートデータソース・ローカルデータソースなど、**プロセス外依存と直接やりとりする**オブジェクトを含む。
- プロセス外依存の **唯一の情報源（single source of truth）** を管理する。
- `App` がこれを参照して `Repository` の `Impl` を実装する。

## DI と抽象化の方針

### 抽象化は protocol ではなく struct

- `Repository` など抽象化が必要なオブジェクトは **struct で定義** する。**protocol による抽象化は原則行わない。**
- 差し替え可能性は、振る舞いをクロージャ（プロパティ）として持つ struct で表現する。テスト・プレビュー用の差し替えや本番実装（`Impl`）は、protocol の準拠型ではなく struct のインスタンス生成で行う。
- struct の型定義は `Core` に置き、本番実装（`Infra` を用いて振る舞いを構築するインスタンス）は `App` で組み立てる。

```swift
// Core: 型定義（struct）
struct UserRepository {
    var fetch: (User.ID) async throws -> User
}

// App: Infra を使って本番インスタンス（Impl）を構築
extension UserRepository {
    static func live(client: APIClient) -> UserRepository {
        UserRepository(fetch: { id in try await client.getUser(id) })
    }
}
```

### DI は SwiftUI の EnvironmentValues 経由

- `Repository` や UseCase の DI は **SwiftUI の `EnvironmentValues`** で行う。
- 各依存に `EnvironmentValues` の拡張（エントリ）を定義し、`App` で本番インスタンスを注入する。
- View 側では **`@Environment`** で `Repository` や UseCase を取り出して利用する。

```swift
// Core or Feature: EnvironmentValues に登録
extension EnvironmentValues {
    @Entry var userRepository = UserRepository(fetch: { _ in fatalError("not injected") })
}

// App: 本番インスタンスを注入
ContentView()
    .environment(\.userRepository, .live(client: apiClient))

// View: @Environment で取り出して使う
struct ProfileView: View {
    @Environment(\.userRepository) private var userRepository
    // ...
}
```

## 状態管理（Store）

アプリ起動中に `Repository` から取得した値をキャッシュし、アプリ全体に状態を同期させたい場合は、**Store オブジェクト**で状態を管理する。

- Store は Observation の **`@Observable`** と **`@MainActor`** を付与した **`final class`** とする。
  - （`Repository` は struct で定義するが、Store は状態を保持・共有する参照型のため class とする。両者の使い分けに注意。）
- Store の状態は Store 内に **カプセル化**し（stored property は `private` / `private(set)`）、**公開した API（メソッド・computed property）を通じてのみ**状態の共有・更新を行う。
- Store も **`@Environment` で DI できるようにする**。`App` モジュールで `Repository` を assemble して Store をインスタンス化し、DI する。
  - `@Observable` なオブジェクトの注入・取得は、`EnvironmentValues` の key ではなく **オブジェクト型ベース**の `.environment(_:)` / `@Environment(_:)` を用いる。

```swift
// Core: Store 定義（状態はカプセル化し、公開 API 経由で共有・更新）
@MainActor
@Observable
final class SessionStore {
    private(set) var currentUser: User?

    private let userRepository: UserRepository

    init(userRepository: UserRepository) {
        self.userRepository = userRepository
    }

    func load(id: User.ID) async throws {
        currentUser = try await userRepository.fetch(id)
    }
}

// App: Repository を assemble して Store をインスタンス化し DI
ContentView()
    .environment(SessionStore(userRepository: .live(client: apiClient)))

// View: @Environment で取り出して使う
struct RootView: View {
    @Environment(SessionStore.self) private var sessionStore
    // ...
}
```

## テスト方針

テストの方針・対象・書き方は [testing.md](testing.md) を参照すること。
