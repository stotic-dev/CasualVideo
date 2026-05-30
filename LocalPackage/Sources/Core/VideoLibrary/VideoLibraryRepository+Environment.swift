//
//  VideoLibraryRepository+Environment.swift
//  Core
//
//  VideoLibraryRepository を EnvironmentValues 経由で DI するためのエントリ定義。
//

import SwiftUI

extension EnvironmentValues {

    /// 写真ライブラリ Repository の DI エントリ。
    ///
    /// 本番インスタンスは `App` が `Infra` を用いて構築し `.environment(\.videoLibraryRepository, .live(...))` で注入する。
    /// 未注入時は空の結果を返すスタブ。
    @Entry public var videoLibraryRepository: VideoLibraryRepository = .unimplemented
}

extension VideoLibraryRepository {

    /// 未注入時のフォールバック。許可なし・空一覧を返す。
    static let unimplemented = VideoLibraryRepository(
        authorizationStatus: { .notDetermined },
        requestAuthorization: { .denied },
        fetchVideos: { [] },
        loadThumbnail: { _, _ in nil },
        loadPlayerItem: { _ in nil }
    )
}
