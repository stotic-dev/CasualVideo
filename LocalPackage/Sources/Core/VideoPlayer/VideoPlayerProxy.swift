//
//  VideoPlayerProxy.swift
//  Core
//
//  AVPlayer 操作を抽象化する Proxy 型定義。
//
//  再生エンジン（AVPlayer / AVPlayerItem）の操作を View 内で直接行うと、UI 表示の責務と
//  プレイヤー操作の責務が混ざり、テスタビリティも下がる。そこで操作をこの Proxy で抽象化し、
//  本番の再生エンジンは `Infra` の Client に閉じ込める（`VideoLibraryRepository` と同じ方針）。
//
//  - 抽象化は protocol ではなく struct + クロージャで表現する（docs/architecture.md）。
//  - 型定義は `Core` に置き、本番実装（`.live`）は `App` が `Infra` の Client を用いて構築する。
//  - 再生レイヤー（AVPlayerLayer）へのバインドに必要な `AVPlayer` は `player()` で取得する。
//    これは「描画用の参照取得」であり、再生・停止などの「操作」はメソッド経由で行う。
//

import AVFoundation

/// 動画プレイヤーの操作を抽象化する Proxy。View / Store はこの抽象を介して再生エンジンを操作する。
public struct VideoPlayerProxy: Sendable {

    /// 再生レイヤーへバインドするための `AVPlayer` を返す（描画用）。
    ///
    /// 操作（再生・停止など）はこの Proxy のメソッド経由で行い、ここで得た `AVPlayer` を
    /// 直接操作しないこと（責務分離・テスタビリティのため）。
    public var player: @MainActor @Sendable () -> AVPlayer?

    /// 描画レイヤーへ player をバインドし、その layer で PIP を構成する（描画面セットアップ）。
    ///
    /// `player()` と同じ「描画バインドの境界」として AVPlayerLayer を受け渡す。
    /// player の layer へのバインド（VideoPlayerClient の責務）と、その layer での PIP 構成
    /// （PictureInPictureClient の責務）という複数 Infra をまたぐ手順は `App` の `.live` が組み立てる。
    public var attachPlayerLayer: @MainActor @Sendable (AVPlayerLayer) -> Void

    /// 自動 PIP 起動（F-3）の有効/無効を切り替える。
    public var setPictureInPictureEnabled: @MainActor @Sendable (Bool) -> Void

    /// 指定アセットの動画を読み込み、再生を開始する。読み込み成否を返す。
    public var loadAndPlay: @Sendable (_ id: VideoAsset.ID) async -> Bool

    /// 再生を再開する。
    public var play: @MainActor @Sendable () -> Void

    /// 再生を一時停止する。
    public var pause: @MainActor @Sendable () -> Void

    /// 音声ミュートを切り替える（F-7 で使用予定）。
    public var setMuted: @MainActor @Sendable (_ muted: Bool) -> Void

    /// バックグラウンド再生・PIP（F-3）のためにオーディオセッションを構成・アクティブ化する。
    ///
    /// PIP・バックグラウンド継続には `.playback` カテゴリでのオーディオセッションが必要なため、
    /// 再生開始の前に呼ぶ。プロセス外（システムのオーディオセッション）への設定は `Infra` に閉じる。
    public var prepareForBackgroundPlayback: @MainActor @Sendable () -> Void

    /// 現在再生中アイテムの再生完了を購読する。完了のたびに渡したハンドラが呼ばれる。
    ///
    /// プレイリストの連続再生（F-4: 1 動画の再生終了で次へ自動遷移）の起点。
    /// 操作（購読登録）はメインアクター上で行う。
    public var observeDidPlayToEnd: @MainActor @Sendable (_ handler: @escaping @MainActor @Sendable () -> Void) -> Void

    /// 指定秒へシークする（シークバー操作 / F-6）。
    public var seek: @MainActor @Sendable (_ seconds: TimeInterval) -> Void

    /// 再生進捗（現在位置・総再生時間）を一定間隔で購読する。更新のたびにハンドラが呼ばれる。
    ///
    /// シークバーの位置・長さ表示（F-6）の起点。再生エンジンの時刻監視は `Infra` に隔離する。
    public var observeProgress: @MainActor @Sendable (_ handler: @escaping @MainActor @Sendable (PlaybackProgress) -> Void) -> Void

    public init(
        player: @escaping @MainActor @Sendable () -> AVPlayer? = { nil },
        attachPlayerLayer: @escaping @MainActor @Sendable (AVPlayerLayer) -> Void = { _ in },
        setPictureInPictureEnabled: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
        loadAndPlay: @escaping @Sendable (_ id: VideoAsset.ID) async -> Bool = { _ in false },
        play: @escaping @MainActor @Sendable () -> Void = {},
        pause: @escaping @MainActor @Sendable () -> Void = {},
        setMuted: @escaping @MainActor @Sendable (_ muted: Bool) -> Void = { _ in },
        prepareForBackgroundPlayback: @escaping @MainActor @Sendable () -> Void = {},
        observeDidPlayToEnd: @escaping @MainActor @Sendable (_ handler: @escaping @MainActor @Sendable () -> Void) -> Void = { _ in },
        seek: @escaping @MainActor @Sendable (_ seconds: TimeInterval) -> Void = { _ in },
        observeProgress: @escaping @MainActor @Sendable (_ handler: @escaping @MainActor @Sendable (PlaybackProgress) -> Void) -> Void = { _ in }
    ) {
        self.player = player
        self.attachPlayerLayer = attachPlayerLayer
        self.setPictureInPictureEnabled = setPictureInPictureEnabled
        self.loadAndPlay = loadAndPlay
        self.play = play
        self.pause = pause
        self.setMuted = setMuted
        self.prepareForBackgroundPlayback = prepareForBackgroundPlayback
        self.observeDidPlayToEnd = observeDidPlayToEnd
        self.seek = seek
        self.observeProgress = observeProgress
    }
}
