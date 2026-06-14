//
//  PlaybackStore.swift
//  Library
//
//  再生中のセッション状態をアプリ全体で同期する Store（F-3 PIP 復帰 / F-4 連続再生の起点）。
//
//  従来 `VideoPlayerScreen`（モーダル）が `PlaylistStore` を `@State` で保持していたが、
//  PIP へ移行する際にモーダルを閉じると Store ごと破棄され、PIP の「戻る」で復帰しても
//  再生位置・順序を失い先頭から再生し直しになる。そこで再生セッション（PlaylistStore）と
//  全画面プレイヤーの提示状態をモーダルの外（アプリ全体で同期する Store）へ持ち上げ、
//  PIP 中もセッションを生存させることで、復帰時に再生を中断せず元の状態へ戻せるようにする。
//
//  - 提示（全画面プレイヤーの表示/非表示）は `isPlayerPresented` で表す。
//  - PIP の「戻る」要求は `VideoPlayerProxy.observePictureInPictureRestore` を購読し、
//    `isPlayerPresented` を true に戻すことで全画面へ復帰する。
//
//  Store の方針（@Observable / @MainActor / 状態のカプセル化 / Environment 注入）は
//  docs-internal/architecture.md「状態管理（Store）」を参照。
//

import Core
import Observation

/// 再生中のセッション状態を管理する Store。連続再生 Store の生成・保持と全画面プレイヤーの提示状態を持つ。
///
/// `App` が assemble して Environment へ型ベースで注入し、一覧・アルバム・再生画面が
/// `@Environment(PlaybackStore.self)` で共有参照する。特定画面に依存せず、再生セッションという
/// ドメイン状態とその提示状態のみを扱う。
@Observable
@MainActor
public final class PlaybackStore {

    /// 再生セッションの読み込み進行状態。再生画面の表示状態の元になる。
    public enum Phase: Sendable, Equatable {
        /// セッション未開始。
        case idle
        /// 再生リソースの取得中（取得前を含む）。
        case loading
        /// 再生可能。
        case ready
        /// プレイリストが空・取得失敗等で再生できない。
        case failed
    }

    /// 現在の連続再生 Store。
    ///
    /// 未再生時は空の Store（`totalCount == 0`）を保持し、`start()` のたびに実プレイリストの
    /// Store へ差し替える。常に非 nil とすることで、表示側（`VideoPlayerScreen`）の optional 連鎖を避ける。
    /// `PlaylistStore` は Feature 内部の型のため、この Store も Library 内に閉じて公開する（internal）。
    private(set) var playlistStore: PlaylistStore

    /// 再生セッションの進行状態。
    public private(set) var phase: Phase = .idle

    /// 全画面プレイヤー（モーダル）を提示中かどうか。
    ///
    /// PIP へ移行すると false（モーダルは閉じるがセッションは生存）。PIP の「戻る」で true に戻る。
    public var isPlayerPresented = false

    /// Chromecast 接続中かどうか。接続時は再生中アセットを Cast デバイスへ引き継ぐ。
    public private(set) var isCasting = false

    private let playerProxy: VideoPlayerProxy
    private let nowPlayingInfoProxy: NowPlayingInfoProxy
    /// 再生開始時の初期値（ミュート・速度 / F-7）を供給する設定 Store。
    private let settingsStore: SettingsStore
    /// Chromecast 操作の抽象。セッション接続購読・メディアロードを委譲する。
    private let castProxy: CastProxy

    public init(
        playerProxy: VideoPlayerProxy,
        nowPlayingInfoProxy: NowPlayingInfoProxy,
        settingsStore: SettingsStore,
        castProxy: CastProxy = CastProxy()
    ) {
        self.playerProxy = playerProxy
        self.nowPlayingInfoProxy = nowPlayingInfoProxy
        self.settingsStore = settingsStore
        self.castProxy = castProxy
        // 未再生時の空セッション。start() で実プレイリストの Store に差し替える。
        self.playlistStore = PlaylistStore(playerProxy: playerProxy, nowPlayingInfoProxy: nowPlayingInfoProxy)

        // PIP の「戻る」で全画面プレイヤーへ復帰する。セッション（playlistStore）は生存しているため、
        // 再提示するだけで再生を中断せず元の状態（位置・順序）から続けられる。
        playerProxy.observePictureInPictureRestore { [weak self] in
            self?.isPlayerPresented = true
        }

        // Cast セッションの接続を購読する。接続時に現在再生中のローカル動画を Chromecast へ引き継ぐ
        // （ローカルアセットの書き出し・HTTP 配信・ロードは CastProxy の本番実装が App で組み立てる）。
        castProxy.observeSessionState { [weak self] state in
            self?.handleCastSessionState(state)
        }
    }

    /// 固定プレイリストで再生を開始し、全画面プレイヤーを提示する（全動画 / 手動選択 / 一覧セル）。
    public func start(playlist: [VideoAsset], startIndex: Int = 0) {
        presentAndLoad(startIndex: startIndex) { playlist }
    }

    /// 再生開始時にプレイリストを動的取得して再生を開始する（アルバム単位 / F-6）。
    public func start(startIndex: Int = 0, playlistProvider: @escaping () async -> [VideoAsset]) {
        presentAndLoad(startIndex: startIndex, provider: playlistProvider)
    }

    /// PIP へ移行する。開始完了後に全画面プレイヤーを閉じる（セッションは生存させ続ける）。
    ///
    /// 先にモーダルを閉じると描画レイヤーが外れて PIP 遷移が中断されるため、開始完了を待つ。
    public func enterPictureInPicture() {
        playerProxy.startPictureInPicture { [weak self] in
            self?.isPlayerPresented = false
        }
    }

    /// 閉じる導線で再生セッションを完全停止・破棄し、全画面プレイヤーを閉じる。
    ///
    /// 再生画面（モーダル）の閉じるボタン / エラー時の閉じる導線から呼ぶ。PIP へ移行する
    /// `enterPictureInPicture()`（セッションを生存させる）とは対照的に、ここでは再生・PIP・
    /// Now Playing Info をすべて止め、セッション（`playlistStore`）を空の新規 Store へ差し替えて
    /// 破棄する（docs-internal/architecture.md「状態管理（Store）」の方針: 状態更新は公開 API 経由）。
    public func stop() {
        // PIP 小窓が出ていれば畳む → 再生エンジンを完全停止（item 解放）→
        // Now Playing をクリア → オーディオセッションを非アクティブ化、の順で全停止する。
        playerProxy.stopPictureInPicture()
        playerProxy.stop()
        nowPlayingInfoProxy.clearNowPlayingInfo()
        playerProxy.deactivateAudioSession()
        // セッションを破棄: 空の新規 PlaylistStore に差し替え、進行状態を未開始へ戻す。
        playlistStore = PlaylistStore(playerProxy: playerProxy, nowPlayingInfoProxy: nowPlayingInfoProxy)
        phase = .idle
        // モーダルを閉じる（提示状態の非提示化）。
        isPlayerPresented = false
    }

    // MARK: - Private

    /// Cast セッションの接続状態変化に応じて、再生中アセットの引き継ぎを行う。
    ///
    /// 接続時は端末側のローカル再生を止めたうえで、現在再生中のアセットを Chromecast へ
    /// ロードして再生する（再生面は Chromecast に一本化し、二重再生を避ける）。
    /// セッション（プレイリスト・再生位置）は保持するため、切断後はその位置から再開できる。
    private func handleCastSessionState(_ state: CastSessionState) {
        switch state {
        case .connected:
            isCasting = true
            // 端末側の再生は止める（Cast 中はローカルプレイヤーを再生させない）。
            playlistStore.pause()
            guard let asset = playlistStore.currentAsset else { return }
            Task { _ = await castProxy.loadAndPlay(asset.id) }
        case .disconnected:
            isCasting = false
        }
    }

    private func presentAndLoad(startIndex: Int, provider: @escaping () async -> [VideoAsset]) {
        // 取得を待たずに全画面プレイヤーを提示し、ローディングを見せる。
        phase = .loading
        isPlayerPresented = true
        // PIP・バックグラウンド再生（F-3）のためのオーディオセッションを再生前に構成する。
        playerProxy.prepareForBackgroundPlayback()

        Task {
            // プレイリストを供給する（アルバム単位は最新内容を動的取得する / F-6）。
            let playlist = await provider()
            guard !playlist.isEmpty else {
                phase = .failed
                return
            }
            // 共有 Store が保持する再生デフォルト（ミュート・速度 / F-7）を初期値として適用する。
            let settings = settingsStore.settings
            let store = PlaylistStore(
                playerProxy: playerProxy,
                nowPlayingInfoProxy: nowPlayingInfoProxy,
                isMuted: settings.isMuted,
                playbackRate: settings.playbackRate
            )
            playlistStore = store
            await store.start(playlist: playlist, from: startIndex)
            // 再生開始できたか（=対象アセットが選択できたか）で readiness を判定する。
            phase = store.currentAsset == nil ? .failed : .ready
        }
    }
}
