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

    public init(
        player: @escaping @MainActor @Sendable () -> AVPlayer? = { nil },
        loadAndPlay: @escaping @Sendable (_ id: VideoAsset.ID) async -> Bool = { _ in false },
        play: @escaping @MainActor @Sendable () -> Void = {},
        pause: @escaping @MainActor @Sendable () -> Void = {},
        setMuted: @escaping @MainActor @Sendable (_ muted: Bool) -> Void = { _ in },
        prepareForBackgroundPlayback: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.player = player
        self.loadAndPlay = loadAndPlay
        self.play = play
        self.pause = pause
        self.setMuted = setMuted
        self.prepareForBackgroundPlayback = prepareForBackgroundPlayback
    }
}
