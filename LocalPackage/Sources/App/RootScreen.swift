//
//  RootScreen.swift
//  App
//
//  アプリのルート画面。依存を assemble し、Environment へ DI する。
//

import Core
import Library
import SwiftUI

public struct RootScreen: View {

    // body 再評価のたびに再生成されないよう、本番 Repository は @State で安定保持する。
    // （Repository 内のサムネイルキャッシュを生存させ続けるため。）
    @State private var videoLibraryRepository = VideoLibraryRepository.live()

    public static func make() -> some View {
        RootScreen()
    }

    public init() {}

    public var body: some View {
        VideoLibraryScreen.make()
            // Infra を用いて構築した本番 Repository を DI する。
            .environment(\.videoLibraryRepository, videoLibraryRepository)
            .environment(VideoLibraryStore(repository: videoLibraryRepository))
    }
}
