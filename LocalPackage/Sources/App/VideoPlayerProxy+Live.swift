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
    static func live(client: VideoPlayerClient) -> VideoPlayerProxy {
        VideoPlayerProxy(
            player: { client.player },
            loadAndPlay: { id in await client.loadAndPlay(localIdentifier: id) },
            play: { client.play() },
            pause: { client.pause() },
            setMuted: { client.setMuted($0) }
        )
    }
}
