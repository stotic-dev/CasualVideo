//
//  VideoPlayerProxy+Live.swift
//  App
//
//  Infra（VideoPlayerClient）を用いて VideoPlayerProxy の本番インスタンスを組み立てる。
//

import Core
import Infra

extension VideoPlayerProxy {

    /// AVPlayer 再生エンジン（`VideoPlayerClient`）を用いた本番インスタンス。
    ///
    /// 操作はすべて Client へ委譲する。`VideoPlayerClient` は `@MainActor` final class（= Sendable）のため、
    /// Proxy のクロージャから安全に参照できる。
    @MainActor
    static func live(
        client: VideoPlayerClient,
        audioSession: AudioSessionClient = AudioSessionClient()
    ) -> VideoPlayerProxy {
        VideoPlayerProxy(
            player: { client.player },
            loadAndPlay: { id in await client.loadAndPlay(localIdentifier: id) },
            play: { client.play() },
            pause: { client.pause() },
            setMuted: { client.setMuted($0) },
            // バックグラウンド再生・PIP（F-3）のためのオーディオセッション設定を Infra へ委譲。
            prepareForBackgroundPlayback: { audioSession.activatePlayback() },
            // プレイリスト連続再生（F-4）のための再生完了購読を Infra へ委譲。
            observeDidPlayToEnd: { client.observeDidPlayToEnd($0) }
        )
    }
}
