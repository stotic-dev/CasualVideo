//
//  CastClient.swift
//  Infra
//
//  GoogleCast SDK との唯一の窓口。
//
//  Cast コンテキスト（`GCKCastContext`）の初期化、セッション接続状態の監視、メディアのロードといった
//  プロセス外依存（Cast デバイス / SDK）への I/O をこの Client に閉じ込める。
//  上位（`App` の assemble 層）の都合は持ち込まず、SDK 操作の単純なコマンド／クエリだけを公開する。
//

import Foundation
#if canImport(GoogleCast)
import GoogleCast

/// Chromecast の receiver application ID（Cast Developer Console 登録値）。
private let receiverApplicationID = "8385AAF2"
#endif

/// GoogleCast SDK と直接やりとりする単一責務の Client。
///
/// SDK 型（`GCKCastContext` / `GCKSessionManager` / `GCKRemoteMediaClient`）はこの Client に隔離し、
/// `App` / `Features` / `Core` からは触れさせない。
///
/// GoogleCast は iOS スライスのみ提供のため、SDK を利用する処理は `#if canImport(GoogleCast)` で
/// ガードする。macOS（`swift test` のホストビルド等）では型だけが存在し、各操作は no-op となる。
@MainActor
public final class CastClient: NSObject {

    /// セッション接続状態の変化を上位へ通知するハンドラ。接続=true / 切断=false。
    private var sessionStateHandler: ((Bool) -> Void)?

    /// Cast デバイス側の再生状態を上位へ通知するハンドラ。
    private var remoteStateHandler: ((RemotePlaybackSnapshot) -> Void)?

    /// 再生位置を周期的にポーリングするタスク（接続中のみ稼働）。
    private var pollingTask: Task<Void, Never>?

    /// 多重初期化を避けるためのフラグ。
    private var didSetUp = false

    public override init() {
        super.init()
    }

    /// Cast コンテキストを初期化する（receiver application ID を設定）。初回のみ実行する。
    ///
    /// アプリ起動時に一度だけ呼ぶ。複数回呼ばれても安全（idempotent）。
    public func setUp() {
        #if canImport(GoogleCast)
        guard !didSetUp else { return }
        didSetUp = true

        let criteria = GCKDiscoveryCriteria(applicationID: receiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        GCKCastContext.setSharedInstanceWith(options)

        GCKCastContext.sharedInstance().sessionManager.add(self)
        #endif
    }

    /// セッション接続状態を購読する。接続・切断のたびにハンドラが呼ばれる。
    public func observeSessionState(_ handler: @escaping (Bool) -> Void) {
        sessionStateHandler = handler
    }

    /// Cast デバイス側の再生状態を購読する。接続中は周期的に最新状態が通知される。
    public func observeRemoteState(_ handler: @escaping (RemotePlaybackSnapshot) -> Void) {
        remoteStateHandler = handler
    }

    /// Cast デバイスの再生を再開する。
    public func playRemote() {
        #if canImport(GoogleCast)
        currentRemoteMediaClient()?.play()
        #endif
    }

    /// Cast デバイスの再生を一時停止する。
    public func pauseRemote() {
        #if canImport(GoogleCast)
        currentRemoteMediaClient()?.pause()
        #endif
    }

    /// Cast デバイスを指定秒（絶対位置）へシークする。
    public func seekRemote(to seconds: TimeInterval) {
        #if canImport(GoogleCast)
        let options = GCKMediaSeekOptions()
        options.interval = seconds
        // interval を現在位置からの相対ではなく絶対位置として扱う。
        options.relative = false
        currentRemoteMediaClient()?.seek(with: options)
        #endif
    }

    /// 現在 Cast セッションが接続済みかどうかを返す。
    public func isConnected() -> Bool {
        #if canImport(GoogleCast)
        guard didSetUp else { return false }
        return GCKCastContext.sharedInstance().sessionManager.hasConnectedSession()
        #else
        return false
        #endif
    }

    /// 指定 URL の動画を Cast デバイスへロードして再生する。ロード要求を発行できたかを返す。
    ///
    /// - Parameters:
    ///   - url: デバイスが取得可能な HTTP(S) の動画 URL。
    ///   - contentType: 動画の MIME タイプ（例: `video/mp4`）。
    ///   - title: Now Playing 表示用のタイトル。
    public func loadMedia(url: URL, contentType: String, title: String) -> Bool {
        #if canImport(GoogleCast)
        guard didSetUp,
              let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession,
              let remoteMediaClient = session.remoteMediaClient
        else { return false }

        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(title, forKey: kGCKMetadataKeyTitle)

        let mediaInfoBuilder = GCKMediaInformationBuilder(contentURL: url)
        mediaInfoBuilder.streamType = .buffered
        mediaInfoBuilder.contentType = contentType
        mediaInfoBuilder.metadata = metadata
        let mediaInfo = mediaInfoBuilder.build()

        let requestBuilder = GCKMediaLoadRequestDataBuilder()
        requestBuilder.mediaInformation = mediaInfo
        requestBuilder.autoplay = true

        // `loadMedia(with:)` は SDK の `loadMediaWithLoadRequestData:` の Swift 名。
        remoteMediaClient.loadMedia(with: requestBuilder.build())
        return true
        #else
        return false
        #endif
    }

    // MARK: - Private（再生状態の同期）

    #if canImport(GoogleCast)
    /// 現在のセッションの `GCKRemoteMediaClient` を返す。
    private func currentRemoteMediaClient() -> GCKRemoteMediaClient? {
        guard didSetUp else { return nil }
        return GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient
    }

    /// 接続時: リモートメディアクライアントのリスナー登録と位置ポーリングを開始する。
    private func startRemoteStateTracking() {
        currentRemoteMediaClient()?.add(self)
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.emitCurrentState()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// 切断時: リスナー解除とポーリング停止を行う。
    private func stopRemoteStateTracking() {
        currentRemoteMediaClient()?.remove(self)
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 現在の Cast デバイス状態を組み立てて上位へ通知する。
    private func emitCurrentState() {
        guard let client = currentRemoteMediaClient() else { return }
        let position = client.approximateStreamPosition()
        let duration = client.mediaStatus?.mediaInformation?.streamDuration ?? 0
        let isPlaying = client.mediaStatus?.playerState == .playing
        remoteStateHandler?(
            RemotePlaybackSnapshot(
                position: position.isFinite ? position : 0,
                duration: duration.isFinite ? duration : 0,
                isPlaying: isPlaying
            )
        )
    }
    #endif
}

// MARK: - GCKSessionManagerListener

#if canImport(GoogleCast)
extension CastClient: GCKSessionManagerListener {

    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        Task { @MainActor in
            self.sessionStateHandler?(true)
            self.startRemoteStateTracking()
        }
    }

    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKSession) {
        Task { @MainActor in
            self.sessionStateHandler?(true)
            self.startRemoteStateTracking()
        }
    }

    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        Task { @MainActor in
            self.stopRemoteStateTracking()
            self.sessionStateHandler?(false)
        }
    }

    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKSession, withError error: Error) {
        Task { @MainActor in
            self.stopRemoteStateTracking()
            self.sessionStateHandler?(false)
        }
    }
}

// MARK: - GCKRemoteMediaClientListener

extension CastClient: GCKRemoteMediaClientListener {

    public nonisolated func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        // 再生/一時停止など状態変化をポーリングを待たず即時反映する。
        Task { @MainActor in self.emitCurrentState() }
    }
}
#endif
