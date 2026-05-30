# 0001. 動画サムネイルのキャッシュ戦略

- ステータス: 採用
- 日付: 2026-05-30
- 関連: F-1（写真ライブラリの動画一覧）, `docs/architecture.md`, `docs/requirements.md`（非機能要件: パフォーマンス）

## コンテキスト

F-1 の動画一覧では、各セルが表示時に PhotoKit からサムネイル（`CGImage`）を遅延・非同期で取得する。当初の実装は取得のたびに `PHAsset.fetchAssets` + `PHImageManager.requestImage` を呼んでおり、セルの再表示やスクロール往復のたびに同じ画像をフルで取り直していた。大量動画でのスクロール滑らかさ（非機能要件）を満たすにはキャッシュ戦略が必要だった。

検討にあたり「`AsyncImage` を使えば手軽にキャッシュできないか」という案も挙がった。

## 決定

サムネイルのメモリキャッシュを `Infra`（`PhotoLibraryClient`）の内部に閉じ込め、`NSCache` で実装する。

- `ThumbnailImageManager`（`private final class`）を `PhotoLibraryClient` 内に持たせ、`localIdentifier + size` をキーに `NSCache<NSString, CGImage>` でキャッシュする。キャッシュヒット時は `PHAsset.fetchAssets` を含め PhotoKit へ一切問い合わせない。
- 画像取得は `PHImageManager.default()` から `PHCachingImageManager` に変更し、将来の先読み（`startCachingImages`）拡張の余地を残す。
- `NSCache` / `PHCachingImageManager` はスレッドセーフだが `Sendable` 準拠が無いため、ラッパーを `@unchecked Sendable` とする。値型 `PhotoLibraryClient: Sendable` は維持する。
- `RootScreen` で `Repository` を `@State` で安定保持し、`body` 再評価のたびに `.live()`（= 新しい `PhotoLibraryClient` / キャッシュ）が作り直されてキャッシュが失われるのを防ぐ。

`Repository` のクロージャ署名・`Store`・View は変更しない。キャッシュは上位レイヤーから見えない `Infra` の最適化として隠蔽する。

## 検討した代替案

### `AsyncImage` によるキャッシュ（不採用）

- `AsyncImage` は **URL 専用**。PhotoKit のサムネイルは「`localIdentifier` → `requestImage` → `CGImage`」という流れで URL が存在せず、適用できない。
- 仮に適用できても、`AsyncImage` のキャッシュは内部の `URLSession.shared`（`URLCache`）任せで、SwiftUI からキャッシュ方針を制御する公式 API が無い。狙ったキャッシュ制御はできない。

### `PHCachingImageManager` の先読み（`startCachingImages`）も併せて実装（今回は見送り）

- 可視範囲のサムネイルを事前デコードでき、高速スクロール時の表示遅延を低減できる。
- 一方で可視範囲のトラッキングが必要になり View 側にも変更が及ぶ。MVP 段階では `NSCache` による重複取得の排除で十分と判断し、見送った。`PHCachingImageManager` 自体は採用済みのため、将来の追加は容易。

## 結果

### 利点

- セル再表示・スクロール往復での重複取得がゼロになり、スクロールが滑らかになる。
- 実装が軽量。メモリ逼迫時は `NSCache` により OS が自動でエントリを破棄するため、上限管理が不要。
- キャッシュを `Infra` に隠蔽したことで、`Repository` の抽象（クロージャ署名）や `Store`・View に影響しない。アーキテクチャの依存方向を保てる。

### 留意点 / トレードオフ

- ディスクキャッシュは持たない（メモリのみ）。アプリ再起動後は再取得になる。MVP では許容する。
- キャッシュキーにサイズを含むため、同一アセットでも表示サイズが変わると別エントリになる。
- キャッシュは `Infra` 内のグローバルに近い状態となる。テスト対象は Core / Features のロジック（`docs/testing.md`）であり `Infra` は対象外のため、テスタビリティ上の問題は生じない。

## 将来の拡張余地

- 高速スクロールの体感をさらに改善する場合、`PHCachingImageManager.startCachingImages` による可視範囲の先読みを追加する（View 側で可視範囲トラッキングが必要）。
