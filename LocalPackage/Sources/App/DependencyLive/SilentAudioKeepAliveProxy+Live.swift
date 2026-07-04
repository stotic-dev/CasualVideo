//
//  SilentAudioKeepAliveProxy+Live.swift
//  App
//
//  SilentAudioKeepAliveProxy の本番実装（Impl）。Infra の AVAudioEngine 窓口へ委譲する。
//

import Core
import Infra

extension SilentAudioKeepAliveProxy {

    /// 本番インスタンスを構築する。無音オーディオのループ再生制御を `Infra` の Client へ委譲する。
    ///
    /// - Parameter client: AVAudioEngine による無音 keep-alive の窓口。
    @MainActor
    static func live(client: SilentAudioKeepAliveClient) -> SilentAudioKeepAliveProxy {
        SilentAudioKeepAliveProxy(
            start: { client.start() },
            stop: { client.stop() }
        )
    }
}
