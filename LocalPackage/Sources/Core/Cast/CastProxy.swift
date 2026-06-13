//
//  CastProxy.swift
//  Core
//
//  Chromecast 操作を抽象化する Proxy 型定義。
//
//  Cast SDK（GoogleCast）の `GCKCastContext` / `GCKSessionManager` / `GCKRemoteMediaClient` の
//  操作を View / Store から直接行うと、UI・再生制御の責務に Cast SDK 依存が混ざり、テスタビリティも
//  下がる。そこで操作をこの Proxy で抽象化し、本番の Cast SDK は `Infra` の Client に閉じ込める
//  （`VideoPlayerProxy` と同じ方針）。
//
//  - 抽象化は protocol ではなく struct + クロージャで表現する（docs-internal/architecture.md）。
//  - 型定義は `Core` に置き、本番実装（`.live`）は `App` が `Infra` の Client を用いて構築する。
//

import Foundation

/// Chromecast の操作を抽象化する Proxy。`App` 起動時の初期化と、セッション接続時のメディアロードを担う。
///
/// ローカル（PhotoKit）動画は Chromecast から直接読めないため、`loadAndPlay` の本番実装（`App` の `.live`）が
/// 「アセットをローカルファイルへ書き出し → ローカル HTTP サーバで配信 → その URL を Cast へロード」という
/// 複数 Infra をまたぐ手順を組み立てる（オーケストレーションは assemble 層の責務）。
public struct CastProxy: Sendable {

    /// アプリ起動時に Cast コンテキスト（receiver application ID）を初期化する。
    ///
    /// 初回のみ初期化され、複数回呼ばれても安全（idempotent）。SDK 型の生成は `Infra` に隔離する。
    public var setUp: @MainActor @Sendable () -> Void

    /// Cast セッションの接続状態を購読する。接続・切断のたびにハンドラが呼ばれる。
    ///
    /// 接続時に再生中アセットを Chromecast へ引き継ぐ（`PlaybackStore` が起点）。
    public var observeSessionState: @MainActor @Sendable (_ handler: @escaping @MainActor @Sendable (CastSessionState) -> Void) -> Void

    /// 指定アセットの動画を Chromecast へロードして再生する。ロード成否を返す。
    ///
    /// ローカルアセットを書き出してローカル HTTP 配信し、その URL を Cast へ渡す手順は
    /// `App` の `.live` が組み立てる。
    public var loadAndPlay: @Sendable (_ id: VideoAsset.ID) async -> Bool

    /// 現在 Cast 接続中かどうかを返す。
    public var isConnected: @MainActor @Sendable () -> Bool

    public init(
        setUp: @escaping @MainActor @Sendable () -> Void = {},
        observeSessionState: @escaping @MainActor @Sendable (_ handler: @escaping @MainActor @Sendable (CastSessionState) -> Void) -> Void = { _ in },
        loadAndPlay: @escaping @Sendable (_ id: VideoAsset.ID) async -> Bool = { _ in false },
        isConnected: @escaping @MainActor @Sendable () -> Bool = { false }
    ) {
        self.setUp = setUp
        self.observeSessionState = observeSessionState
        self.loadAndPlay = loadAndPlay
        self.isConnected = isConnected
    }
}
