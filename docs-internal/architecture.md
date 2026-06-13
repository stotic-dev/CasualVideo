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
- **複数の Infra をまたぐオーケストレーション（取得 → 変換 → 別 Infra へ受け渡し、等）はこの `.live`（Impl）ファクトリで組み立てる。** これにより各 Infra Client は単一責務に保たれ、組み合わせの都合は assemble 層に集約される。

```swift
// App: 複数 Infra を組み合わせて Impl を構築する例
extension VideoPlayerProxy {
    static func live(
        playerClient: VideoPlayerClient,        // AVPlayer の窓口
        photoLibraryClient: PhotoLibraryClient  // PhotoKit の窓口
    ) -> VideoPlayerProxy {
        VideoPlayerProxy(
            // 「取得（PhotoKit）→ 差し替え → 再生」という複数 Infra をまたぐ手順はここで組み立てる。
            loadAndPlay: { id in
                guard let item = await photoLibraryClient.loadPlayerItem(localIdentifier: id) else { return false }
                await playerClient.replaceCurrentItem(item)
                await playerClient.play()
                return true
            }
            // ...
        )
    }
}
```

> 補足: orchestration が複雑化し、独立したテストが必要になった場合は、`Infra` と `App` の間に専用の Data 層（DataSource=Infra / Repository=Data）を切り出す選択肢もある。ただし現状はこの assemble 方式を既定とする。

### Features/\<Feature\>

- Feature の粒度でモジュールを切り分ける。
- 画面（View）と、その Feature 特有のビジネスロジックを含む。
- 横断的に使う定義（他 Feature や App と共有するもの）は持たず、`Core` を参照する。
- **その Feature 内でしか参照しないモデル（ドメインモデル・Store・値型など）は Feature 内に置く。**`Core` には上げない（後述「配置スコープ最小化の原則」）。

### Core

- モジュール間をまたぐ定義を含む。
- 例: `Repository` の型定義（`App` でも `Features` でも参照するため `Core` に置く）。後述の通り protocol ではなく **struct** で定義する。
- ドメインモデル、および UseCase（複数 Feature のプレゼンテーションロジックで重複する部分のファサード）を含む。
- **`Core` に置くのは「実際にモジュールをまたいで参照される」定義に限る。** 単一 Feature 内で完結するものを `Core` に置かない（後述「配置スコープ最小化の原則」）。

### 配置スコープ最小化の原則（重要）

**モデルは「実際に参照される最小のスコープ」に置く。`Core` は共有のための置き場であって、デフォルトの置き場ではない。**

- ドメインモデル・Store・値型などを実装するときは、まず **その Feature 内に閉じられないか** を検討する。単一 Feature でしか使わないものは、その `Features/<Feature>` 内に置きカプセル化する。
- **「いつか他でも使うかも」で先回りして `Core` に上げない。** 実際に 2 つ目の参照元（別 Feature や App）が現れた時点で初めて `Core` へ引き上げる。
- 理由:
  - **不要なスコープ拡大を防ぐ。** `Core` に置くと全モジュールから参照可能になり、本来 Feature 内の実装詳細だったものが公開 API（`public`）化してしまう。変更の影響範囲が無用に広がる。
  - **モジュール境界でカプセル化が効く。** Feature 内に閉じておけば `internal` で隠蔽でき、その Feature の関心事として凝集が保たれる。
- 判断基準: **「App もしくは複数の Feature から参照されるか？」が Yes のものだけを `Core` に置く。**それ以外は Feature 内（あるいは Infra 内）に留める。
  - 例: `PlaylistStore` / `PlaybackControlsVisibility` などプレイヤー画面でのみ使う Store は `Features/Library` 内に置く。`VideoAsset` や `Repository` 型のように App・複数 Feature から参照されるものは `Core` に置く。

### Infra

- リモートデータソース・ローカルデータソースなど、**プロセス外依存と直接やりとりする**オブジェクトを含む。
- プロセス外依存の **唯一の情報源（single source of truth）** を管理する。
- `App` がこれを参照して `Repository` の `Impl` を実装する。

#### Infra Client の責務境界（重要）

各 Infra Client は **1 つのプロセス外依存に対する単一責務**に閉じる。次を守ること:

- **Client は「使う側（消費側）の都合」を持ち込まない。** 単純なコマンド／クエリの API だけを公開する。
  - 例: AVPlayer の Client は `replaceCurrentItem(_:)` / `play()` を公開するだけ。「どの動画を再生するか（`localIdentifier` 等）」「取得してから差し替えて再生する」といった**使う側の手順**は持たない。
  - 理由: 使う側を意識した API を Infra に置くと、仕様変更時の影響が Infra まで波及し、変更範囲が広がる。
- **Infra Client 同士を依存させない。** 1 つの Client が別の Client を生成・保持しない（例: AVPlayer の Client が PhotoKit の Client を持たない）。別々のプロセス外依存は疎結合に保つ。
- **複数の Infra を組み合わせた処理（オーケストレーション）は Infra に置かない。** その組み立ては `App` の assemble 層が担う（後述）。

#### フレームワーク型（再生エンジン等）の隔離（重要）

**プロセス外依存を表すフレームワークの型は、その型を直接生成・保持・操作する実装ごと Infra Client に隔離する。** `Features` / `Core` のロジックや View からこれらの型を直接参照・操作しないこと。

- 隔離対象の例（AVFoundation / AVKit / システム機能の窓口）:
  - `AVPlayer` / `AVPlayerItem`（再生エンジン）→ `VideoPlayerClient`
  - `AVPictureInPictureController`（PIP）→ `PictureInPictureClient`
  - `AVAudioSession`（オーディオセッション）→ `AudioSessionClient`
  - 同様に、`PHAsset` 等の PhotoKit 型、永続化・ネットワーク等のフレームワーク型も Infra Client に閉じる。
- **View / Features / Core は、これらの型を直接触らず `Core` の Proxy（struct + クロージャ）経由で操作する。** 操作（再生・停止・PIP 構成など）は Proxy のメソッドで行い、生のフレームワーク型を取り回さない。
- **複数のフレームワーク型をまたぐ手順は `App` の assemble 層（`.live`）でオーケストレーションする。** 各 Infra Client は単一責務に保つ（例: 「player を layer にバインド → その layer で PIP を構成」は `VideoPlayerProxy.live` が `VideoPlayerClient` と `PictureInPictureClient` を組み合わせて組み立てる）。

##### 唯一の例外: 描画サーフェスの所有

UIKit/SwiftUI の都合で **View が所有せざるを得ない「描画サーフェス」型に限り**、View 層が保持してよい。

- 例: `AVPlayerLayer` は `UIView.layerClass` のバッキングレイヤーとして View が所有する（レイアウト追従のため）。これは「再生エンジンの描画面」であり、View の関心事のため例外的に許容する。
- ただし **その描画サーフェスへの操作（player のバインド・PIP コントローラ生成など）は View で行わず、Proxy に渡して Infra に委譲する。** View は「自分が所有するサーフェスを Proxy に引き渡す」だけに留める。
  - 例: `PlayerViewController` は所有する `AVPlayerLayer` を `videoPlayerProxy.attachPlayerLayer(_:)` に渡すのみ。`AVPlayer` のバインドと `AVPictureInPictureController` の生成は Proxy → Infra 側が担う。
- 逆に、`AVPlayer` や `AVPictureInPictureController` のような「エンジン／コントローラ」型を View が直接生成・保持・操作するのは **禁止**（描画サーフェスの例外には含めない）。

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

### Store は特定の画面に依存しない（UI 関連型を扱わない）

- **Store は特定の画面に紐づく存在ではない。** 必要に応じて複数の画面から共有・再利用できるよう、ドメインの状態とロジックのみを持たせる。「○○画面の Store」という前提で画面都合の責務を持ち込まない。
- そのため **Store は UI 関連型（`CGImage` / `UIImage` / SwiftUI の型など）を扱わない。** 状態・公開 API の入出力は、ドメインモデルや値型（`Core` の型）に限定する。
  - 理由: UI 型を Store が持つと、(1) その画面専用になり再利用できない、(2) UI フレームワークへ依存して Store のテスタビリティ（`Core`/`Features` ロジックの純粋なテスト）が下がる、(3) レイヤーの責務境界が曖昧になる。
- **画像など UI 都合のリソース取得は Store を経由しない。** View が `@Environment` で `Repository` を直接取り出し、View のライフサイクル（`.task` 等）で取得・保持する。
  - 例: 動画一覧のサムネイル（`CGImage`）は、`Store` ではなく各セル View が `Repository.loadThumbnail` を直接呼んで `@State` に保持する。`Store` は `VideoAsset` などのドメイン状態のみを管理する。

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

## SwiftUI 実装方針

View の設計（Screen と presentational View の分離、副作用の置き場所、Preview / Snapshot 再現性）は [swiftui.md](swiftui.md) を参照すること。

## テスト方針

テストの方針・対象・書き方は [testing.md](testing.md) を参照すること。
