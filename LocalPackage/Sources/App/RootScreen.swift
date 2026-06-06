//
//  RootScreen.swift
//  App
//
//  アプリのルート画面。依存を assemble し、Environment へ DI する。
//

import Core
import Infra
import Library
import SwiftUI

public struct RootScreen: View {

    // PhotoKit への唯一の窓口。サムネイル一覧（Repository）と再生アイテム取得（Proxy）で共有する。
    // サムネイルキャッシュを生存させ続けるため @State で安定保持する。
    @State private var photoLibraryClient: PhotoLibraryClient

    // body 再評価のたびに再生成されないよう、本番 Repository は @State で安定保持する。
    @State private var videoLibraryRepository: VideoLibraryRepository

    // 再生エンジン（AVPlayer）は単一インスタンスを生存させ続ける必要があるため @State で安定保持する。
    @State private var videoPlayerClient = VideoPlayerClient()

    public static func make() -> some View {
        RootScreen()
    }

    public init() {
        let photoLibraryClient = PhotoLibraryClient()
        _photoLibraryClient = State(initialValue: photoLibraryClient)
        _videoLibraryRepository = State(initialValue: .live(client: photoLibraryClient))
    }

    public var body: some View {
        VideoLibraryScreen.make()
            // Infra を用いて構築した本番 Repository / Proxy を DI する。
            .environment(\.videoLibraryRepository, videoLibraryRepository)
            .environment(VideoLibraryStore(repository: videoLibraryRepository))
            .environment(
                \.videoPlayerProxy,
                .live(playerClient: videoPlayerClient, photoLibraryClient: photoLibraryClient)
            )
    }
}
