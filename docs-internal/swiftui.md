# SwiftUI 実装方針

CasualVideo における SwiftUI の View 設計ルールを定義する。実装・レビュー時はこのルールに従うこと。モジュール構成・依存ルールは [architecture.md](architecture.md)、状態管理（Store）は [architecture.md の「状態管理（Store）」](architecture.md#状態管理store) を参照。

## 基本原則: Screen と View を分離する

View を 2 種類に役割分担する。

| 種別 | 役割 | 副作用 | 状態の取得元 |
| --- | --- | --- | --- |
| **Screen** | Feature の公開エントリ。`Store` を参照し、ライフサイクルに紐づく副作用を担う。 | 持つ（`.task` / `.onAppear` など） | `@Environment`（Repository / Store）から取得 |
| **View**（presentational） | 受け取った状態を表示し、ユーザー操作を上位へ伝えるだけ。 | **持たない** | **イニシャライザ**で受け取り `let` / `@State` / `@Binding` として保持 |

### Screen が副作用を担う

- `.task` / `.onAppear` / `.refreshable` など、**ライフサイクルに紐づく副作用（データ読み込み・初期化）は Screen で実装する。**
- Screen は `Store` を **`@Environment` で取得**し（Store の assemble・DI は `App`／Root 層が担う。[architecture.md の「状態管理（Store）」](architecture.md#状態管理store) 参照）、`Store` の公開 API を副作用として呼ぶ。`Store` のロード状態を UI の表示状態（ViewState）へ変換した値と、ユーザー操作に対応するアクション（クロージャ）を presentational View へ渡す。
  - Store を Screen 内で生成しないため、Screen は単一の `View` で完結する（Environment から Store を生成して `@State` で受け渡す中間層は不要）。

### View は値を受け取って表示するだけ

- presentational View は、表示に必要な状態を **すべてイニシャライザ経由で受け取る**。`let` / `@State`（init で初期化）/ `@Binding` として保持し、表示するだけにとどめる。
- presentational View は **`@Environment` から Repository / Store を取得しない**し、**`.task` / `.onAppear` でのデータ読み込みなどの副作用を持たない**。
- ユーザー操作（再試行ボタンなど）は **クロージャとして init で受け取り**、押下時にそれを呼ぶだけにする。副作用の実体は Screen 側に置く。

## なぜこうするか

- **Preview の容易さ**: presentational View は init に値を渡すだけで任意の状態を再現できる。`Store` や `Repository`、非同期読み込みのスタブを Preview のために用意する必要がない。`.loading` / `.loaded` / `空` / `エラー` といったケースをそれぞれ即座にプレビューできる。
- **Snapshot テストの容易さ**: 後に snapshot テストを導入する際、presentational View に状態を直接注入するだけで様々なケースを安定して検証できる。副作用や外部依存が無いため、テストがフレーク（不安定）になりにくい。
- **責務の分離**: 副作用が Screen の 1 箇所に集約され、表示ロジックと読み込みロジックが混ざらない。

## 実装例

```swift
// Root（App 層）: 依存を assemble し、Store を Environment へ DI する。
//   Store の生成・注入は Feature ではなく App／Root が担う（architecture.md 参照）。
public struct RootScreen: View {
    @State private var videoLibraryRepository = VideoLibraryRepository.live()

    public var body: some View {
        VideoLibraryScreen.make()
            .environment(\.videoLibraryRepository, videoLibraryRepository)
            .environment(VideoLibraryStore(repository: videoLibraryRepository))
    }
}

// Screen: 公開エントリ。Store は Environment から取得し、副作用（ライフサイクル）を担う。
//   Store を生成しないため中間層は不要で、Screen は単一の View で完結する。
public struct VideoLibraryScreen: View {
    @Environment(VideoLibraryStore.self) private var store

    public init() {}
    public static func make() -> some View { VideoLibraryScreen() }

    public var body: some View {
        // Store のロード状態を UI の表示状態（ViewState）へ変換して渡す。
        // Store は UI 関連型を持たない（architecture.md 参照）ため、変換は View 層が担う。
        VideoLibraryView(state: VideoLibraryViewState(loadState: store.loadState)) {
            await store.reload()
        }
        .task {
            // ライフサイクルに紐づく副作用は Screen 側に置く。
            await store.load()
        }
    }
}

// 表示状態（ViewState）: Store のロード状態を UI 制御の単位へ変換したもの。View 層に置く。
enum VideoLibraryViewState: Equatable {
    case loading
    case empty
    case videos([VideoAsset])
    case unauthorized(VideoLibraryAuthorizationStatus)

    init(loadState: VideoLibraryLoadState) {
        switch loadState {
        case .idle, .loading: self = .loading
        case .loaded(let videos): self = videos.isEmpty ? .empty : .videos(videos)
        case .unauthorized(let status): self = .unauthorized(status)
        }
    }
}

// presentational View: init で受け取った状態を表示するだけ。副作用を持たない。
struct VideoLibraryView: View {
    let state: VideoLibraryViewState
    let onRetry: () async -> Void

    var body: some View { /* state に応じて表示するだけ */ }
}

// Preview: Store も Repository も不要。表示状態を直接注入してケースを再現できる。
#Preview("読み込み完了") {
    VideoLibraryView(state: .videos([.preview]), onRetry: {})
}
#Preview("未許可") {
    VideoLibraryView(state: .unauthorized(.denied), onRetry: {})
}
```

## 例外: View 自身のライフサイクルに不可分な遅延読み込み

`LazyVGrid` のセルごとのサムネイル読み込みのように、**そのセル View の出現に不可分で Screen へ巻き上げられない遅延読み込み**は、例外的に当該 View 内の `.task` で行ってよい。

ただしこの場合も Preview / Snapshot 再現性を保つため、**読み込み結果を init で注入できる口を用意する**（注入されていればそれを表示し、無ければ `.task` で読み込む）。リソース取得自体は [architecture.md の Store 方針](architecture.md#store-は特定の画面に依存しないui-関連型を扱わない)に従い、`Store` ではなく `Repository` を直接呼ぶ。
