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

    // PIP コントローラの窓口。body 再評価のたびに作り直されると保持中の PIP コントローラ・
    // 「戻る」購読を失うため、@State で単一インスタンスを安定保持する。
    @State private var pictureInPictureClient = PictureInPictureClient()

    @State private var nowPlayingInfoClient = NowPlayingInfoClient()

    // 再生デフォルト設定（F-7）の永続化窓口。UserDefaults への単一窓口を安定保持する。
    @State private var userDefaultsClient = UserDefaultsClient()
    
    // MARK: Storeの保持
    
    @State private var videoLibraryStore = VideoLibraryStore()
    // 再生デフォルト設定（F-7）の共有 Store。設定画面・再生画面が型ベースで参照する。
    @State private var settingsStore = SettingsStore()
    // アプリスコープの再生 Store（F-3 PIP 復帰 / F-4 連続再生）。一覧・アルバム・再生画面で共有する。
    @State private var playbackStore: PlaybackStore?

    // 画面が初期化済みかどうか
    @State private var isInitialized = false

    public static func make() -> some View {
        RootScreen()
    }

    public init() {
        let photoLibraryClient = PhotoLibraryClient()
        _photoLibraryClient = State(initialValue: photoLibraryClient)
        _videoLibraryRepository = State(initialValue: .live(client: photoLibraryClient))
    }

    public var body: some View {
        ZStack {
            if isInitialized, let playbackStore {
                VideoLibraryScreen.make()
                // Infra を用いて構築した本番 Repository / Proxy を DI する。
                    .environment(\.videoLibraryRepository, videoLibraryRepository)
                    .environment(
                        \.videoPlayerProxy,
                         .live(
                            playerClient: videoPlayerClient,
                            photoLibraryClient: photoLibraryClient,
                            pictureInPictureClient: pictureInPictureClient
                         )
                    )
                    .environment(
                        \.nowPlayingInfoProxy,
                         .live(nowPlayingInfoClient: nowPlayingInfoClient, photoLibraryClient: photoLibraryClient)
                    )
                    .environment(videoLibraryStore)
                    .environment(settingsStore)
                    .environment(playbackStore)
                // UI関連のDI
                    .environment(\.castComponentResolver, .live)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            // Storeの生成
            videoLibraryStore = .init(repository: videoLibraryRepository)
            let settingsStore = SettingsStore(repository: .live(client: userDefaultsClient))
            self.settingsStore = settingsStore

            // 再生 Store は、PIP コントローラ・再生エンジンと同じ Infra Client 群を共有する
            // Proxy で構築する。これにより PIP の開始・「戻る」購読・描画バインドが単一の
            // PictureInPictureClient / VideoPlayerClient を介して整合する。
            playbackStore = PlaybackStore(
                playerProxy: .live(
                    playerClient: videoPlayerClient,
                    photoLibraryClient: photoLibraryClient,
                    pictureInPictureClient: pictureInPictureClient
                ),
                nowPlayingInfoProxy: .live(
                    nowPlayingInfoClient: nowPlayingInfoClient,
                    photoLibraryClient: photoLibraryClient
                ),
                settingsStore: settingsStore
            )
            isInitialized = true
        }
    }
}
