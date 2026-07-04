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

    // GoogleCast SDK の窓口。Cast コンテキスト初期化・セッション購読を担う単一インスタンスを安定保持する。
    @State private var castClient = CastClient()
    // iOS 27 AVSystemRouting の窓口。observer 登録・セッション保持を担う単一インスタンスを安定保持する。
    @State private var systemRouteCastClient = SystemRouteCastClient()
    // ローカル動画を LAN 上で HTTP 配信するサーバ。Cast セッション中ずっと生存させる必要があるため安定保持する。
    @State private var mediaServer = LocalMediaServer()
    // Cast 接続中のバックグラウンド維持（無音オーディオ keep-alive）の窓口。AVAudioEngine を生存させ続けるため安定保持する。
    @State private var silentAudioKeepAliveClient = SilentAudioKeepAliveClient()

    // MARK: Storeの保持
    
    @State private var videoLibraryStore = VideoLibraryStore()
    // 再生デフォルト設定（F-7）の共有 Store。設定画面・再生画面が型ベースで参照する。
    @State private var settingsStore = SettingsStore()
    // 開発者向け設定の共有 Store。設定画面（開発者セクション）で Cast バックエンドを手動切り替えする。
    @State private var developerSettingsStore: DeveloperSettingsStore?
    // アプリスコープの再生 Store（F-3 PIP 復帰 / F-4 連続再生）。一覧・アルバム・再生画面で共有する。
    @State private var playbackStore: PlaybackStore?
    // 起動時に解決した Cast バックエンド。CastProxy 実装と Cast ボタン UI の両方に同じ値を用いる。
    @State private var castBackend: CastBackend = .googleCast

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
            if isInitialized, let playbackStore, let developerSettingsStore {
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
                    .environment(developerSettingsStore)
                    .environment(playbackStore)
                // UI関連のDI
                    .environment(\.castComponentResolver, .live(backend: castBackend))
            } else {
                ProgressView()
            }
        }
        .onAppear {
            // Storeの生成
            videoLibraryStore = .init(repository: videoLibraryRepository)
            let settingsStore = SettingsStore(repository: .live(client: userDefaultsClient))
            self.settingsStore = settingsStore

            // 開発者向け設定を読み込み、Cast バックエンドを決定する。
            let developerSettingsStore = DeveloperSettingsStore(repository: .live(client: userDefaultsClient))
            self.developerSettingsStore = developerSettingsStore

            // iOS 27 かつメディアデバイス拡張が利用可能なら AVSystemRouting、そうでなければ GoogleCast。
            // 開発者モードの override があればそれを優先する（判定ロジックは Core の純粋関数に閉じる）。
            let isSystemRoutingAvailable: Bool = {
                if #available(iOS 27.0, *) {
                    return SystemRouteCastClient.supportedExtensionAvailable
                } else {
                    return false
                }
            }()
            let backend = CastBackend.resolve(
                override: developerSettingsStore.settings.castBackendOverride,
                isSystemRoutingAvailable: isSystemRoutingAvailable
            )
            self.castBackend = backend

            // 再生 Store は、PIP コントローラ・再生エンジンと同じ Infra Client 群を共有する
            // Proxy で構築する。これにより PIP の開始・「戻る」購読・描画バインドが単一の
            // PictureInPictureClient / VideoPlayerClient を介して整合する。
            // Cast の本番実装を、決定したバックエンドに応じて assemble する。いずれもローカル HTTP
            // サーバ・PhotoKit を組み合わせ、ローカル動画を第三者デバイスへ引き継ぐ手順を構築する。
            let castProxy: CastProxy
            switch backend {
            case .systemRouting:
                castProxy = .systemRouting(
                    client: systemRouteCastClient,
                    mediaServer: mediaServer,
                    photoLibraryClient: photoLibraryClient
                )
            case .googleCast, .auto:
                castProxy = .live(
                    castClient: castClient,
                    mediaServer: mediaServer,
                    photoLibraryClient: photoLibraryClient
                )
            }
            // アプリ起動時に Cast コンテキスト / ルート監視を初期化し、配信サーバを起動する。
            castProxy.setUp()

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
                settingsStore: settingsStore,
                castProxy: castProxy,
                silentAudioKeepAliveProxy: .live(client: silentAudioKeepAliveClient)
            )
            isInitialized = true
        }
    }
}
