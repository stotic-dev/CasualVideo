//
//  SystemRouteCastClient.swift
//  Infra
//
//  iOS 27 `AVSystemRouting` との唯一の窓口。
//
//  メディアデバイス拡張（MDE）経由でシステムのルートピッカーから第三者デバイスへ送出する。
//  GoogleCast SDK の窓口（`CastClient`）と同じ「OS/SDK 窓口」責務で、`AVSystemRouting` の型
//  （`AVSystemRouteController` / `AVSystemRouteSession` 等）をこの Client に隔離する。
//
//  `AVSystemRouting` は iOS 27 提供（macOS スライスなし）のため、利用する処理は
//  `#if canImport(AVSystemRouting)` と `@available(iOS 27.0, *)` でガードする。macOS（`swift test`
//  のホストビルド等）では型だけが存在し、各操作は no-op となる（`CastClient` と同方針）。
//
//  Infra は Core に依存しないため、アセット ID は Core の `VideoAsset.ID` ではなく素の `String` で扱う。
//

import Foundation

#if canImport(AVSystemRouting)
import AVSystemRouting
import CoreMedia
#endif

/// 送出するメディアの配信情報。`App` の assemble 層が PhotoKit 書き出し + ローカル HTTP 配信から組み立てる。
public struct ResolvedCastMedia: Sendable {

    /// デバイスが取得可能な HTTP(S) の動画 URL。
    public let url: URL
    /// 動画の MIME タイプ（例: `video/mp4`）。
    public let mimeType: String
    /// Now Playing 表示用のタイトル。
    public let title: String

    public init(url: URL, mimeType: String, title: String) {
        self.url = url
        self.mimeType = mimeType
        self.title = title
    }
}

/// `AVSystemRouting` と直接やりとりする単一責務の Client。
@MainActor
public final class SystemRouteCastClient: NSObject {

    /// セッション接続状態の変化を上位へ通知するハンドラ。接続=true / 切断=false。
    private var sessionStateHandler: ((Bool) -> Void)?

    /// 現在再生中アセットの ID を取得するプロバイダ（再生セッションが登録する）。
    private var assetIDProvider: (() -> String?)?

    /// アセット ID から配信メディアを解決するクロージャ（`App` が PhotoKit + HTTP サーバで組み立てる）。
    private var mediaResolver: ((String) async -> ResolvedCastMedia?)?

    /// Cast デバイス側の再生状態を上位へ通知するハンドラ。
    private var remoteStateHandler: ((RemotePlaybackSnapshot) -> Void)?

    /// 再生状態を周期的にポーリングするタスク（接続中のみ稼働）。
    private var pollingTask: Task<Void, Never>?

    /// 多重初期化（observer 二重登録）を避けるためのフラグ。
    private var didSetUp = false

    /// 現在の接続状態。
    private var connected = false

    #if canImport(AVSystemRouting)
    /// 進行中のルート / セッション（切断時に停止・解除する）。
    @available(iOS 27.0, *)
    private var currentRoute: AVSystemRoute? {
        get { _currentRoute as? AVSystemRoute }
        set { _currentRoute = newValue }
    }
    @available(iOS 27.0, *)
    private var currentSession: AVSystemRouteSession? {
        get { _currentSession as? AVSystemRouteSession }
        set { _currentSession = newValue }
    }
    // 型を保持するためのストレージ（プロパティに直接 @available 型を置けないため Any で保持）。
    private var _currentRoute: AnyObject?
    private var _currentSession: AnyObject?
    private var _currentMediaSession: AnyObject?
    #endif

    public override init() {
        super.init()
    }

    /// メディアデバイス拡張が利用可能か（iOS 27 以上かつ対応拡張が導入済み）。
    public static var supportedExtensionAvailable: Bool {
        #if canImport(AVSystemRouting)
        if #available(iOS 27.0, *) {
            return AVSystemRouteController.supportedExtensionAvailable
        } else {
            return false
        }
        #else
        return false
        #endif
    }

    /// ルート監視を開始する（observer を登録）。初回のみ実行する。
    ///
    /// 対応するメディアデバイス拡張が導入されていない（`MDESupportedProtocols` 未設定を含む）環境では
    /// AVSystemRouting の初期化が成立しないため、observer 登録を行わず no-op とする。
    /// 実 MDE プロトコル + 拡張ターゲットが揃うまでは常にこのガードで早期 return する。
    public func setUp() {
        #if canImport(AVSystemRouting)
        if #available(iOS 27.0, *) {
            guard Self.supportedExtensionAvailable else { return }
            guard !didSetUp else { return }
            didSetUp = true
            _ = AVSystemRouteController.shared.addObserver(self)
        }
        #endif
    }

    /// セッション接続状態を購読する。接続・切断のたびにハンドラが呼ばれる。
    public func observeSessionState(_ handler: @escaping (Bool) -> Void) {
        sessionStateHandler = handler
    }

    /// 現在再生中アセットの ID プロバイダを登録する。
    public func setAssetIDProvider(_ provider: @escaping () -> String?) {
        assetIDProvider = provider
    }

    /// アセット ID から配信メディアを解決するクロージャを登録する。
    public func setMediaResolver(_ resolver: @escaping (String) async -> ResolvedCastMedia?) {
        mediaResolver = resolver
    }

    /// 現在 Cast セッションが接続済みかどうかを返す。
    public func isConnected() -> Bool {
        connected
    }

    /// Cast デバイス側の再生状態を購読する。接続中は周期的に最新状態が通知される。
    public func observeRemoteState(_ handler: @escaping (RemotePlaybackSnapshot) -> Void) {
        remoteStateHandler = handler
    }

    /// Cast デバイスの再生を再開する。
    public func playRemote() {
        #if canImport(AVSystemRouting)
        if #available(iOS 27.0, *), var control = playbackControl {
            // 存在型は値型扱いのため一度 var に束ねてから設定する（内部実装はクラス参照のためデバイスへ反映される）。
            control.isPlaying = true
        }
        #endif
    }

    /// Cast デバイスの再生を一時停止する。
    public func pauseRemote() {
        #if canImport(AVSystemRouting)
        if #available(iOS 27.0, *), var control = playbackControl {
            control.isPlaying = false
        }
        #endif
    }

    /// Cast デバイスを指定秒（絶対位置）へシークする。
    public func seekRemote(to seconds: TimeInterval) {
        #if canImport(AVSystemRouting)
        if #available(iOS 27.0, *), var control = playbackControl {
            control.currentPlaybackPosition = CMTime(seconds: seconds, preferredTimescale: 600)
        }
        #endif
    }

    #if canImport(AVSystemRouting)
    /// 現在のメディアセッションの再生コントロール。
    @available(iOS 27.0, *)
    private var playbackControl: (any AVInterfaceControllable)? {
        (_currentMediaSession as? AVSystemRouteMediaSession)?.playbackControl
    }

    /// 接続時: 再生状態の周期ポーリングを開始する。
    @available(iOS 27.0, *)
    private func startRemoteStateTracking() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.emitCurrentState()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// 切断時: ポーリングを停止する。
    private func stopRemoteStateTracking() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 現在の Cast デバイス状態を組み立てて上位へ通知する。
    @available(iOS 27.0, *)
    private func emitCurrentState() {
        guard let control = playbackControl else { return }
        let position = control.currentPlaybackPosition.seconds
        let duration = control.timeRange.duration.seconds
        remoteStateHandler?(
            RemotePlaybackSnapshot(
                position: position.isFinite ? position : 0,
                duration: duration.isFinite ? duration : 0,
                isPlaying: control.isPlaying
            )
        )
    }
    #endif
}

// MARK: - AVSystemRouteControllerObserver

#if canImport(AVSystemRouting)
@available(iOS 27.0, *)
extension SystemRouteCastClient: AVSystemRouteControllerObserver {

    public nonisolated func systemRouteController(
        _ controller: AVSystemRouteController,
        handle event: AVSystemRouteEvent
    ) async -> Bool {
        switch event.reason {
        case .activate:
            return await activate(route: event.route)
        case .deactivate:
            await deactivate()
            return true
        @unknown default:
            return false
        }
    }

    /// ルート選択時: 現在再生中アセットを書き出して配信し、セッションを開始する。
    ///
    /// メディアのロードはこのハンドラ内で完結させる（Apple 推奨フロー）。成功で接続状態を通知する。
    @MainActor
    private func activate(route: AVSystemRoute) async -> Bool {
        guard let id = assetIDProvider?(),
              let media = await mediaResolver?(id)
        else {
            return false
        }

        let session = AVSystemRouteSession(url: media.url, mode: .player)
        guard route.addSession(session) else { return false }

        do {
            let mediaSession = try await session.start()
            currentRoute = route
            currentSession = session
            _currentMediaSession = mediaSession
            connected = true
            startRemoteStateTracking()
            sessionStateHandler?(true)
            return true
        } catch {
            route.removeSession(session)
            return false
        }
    }

    /// ルート解除時: セッションを停止して接続状態をクリアする。
    @MainActor
    private func deactivate() {
        stopRemoteStateTracking()
        if let route = currentRoute, let session = currentSession {
            session.stop()
            route.removeSession(session)
        }
        currentRoute = nil
        currentSession = nil
        _currentMediaSession = nil
        connected = false
        sessionStateHandler?(false)
    }
}
#endif
