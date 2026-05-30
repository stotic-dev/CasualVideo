//
//  VideoPlayerProxy+Environment.swift
//  Core
//
//  VideoPlayerProxy を EnvironmentValues 経由で DI するためのエントリ定義。
//

import SwiftUI

extension EnvironmentValues {

    /// 動画プレイヤー Proxy の DI エントリ。
    ///
    /// 本番インスタンスは `App` が `Infra` の `VideoPlayerClient` を用いて構築し、
    /// `.environment(\.videoPlayerProxy, .live(client:))` で注入する。
    /// 未注入時は何もしない（再生不可・操作は no-op）フォールバック。
    @Entry public var videoPlayerProxy = VideoPlayerProxy()
}
