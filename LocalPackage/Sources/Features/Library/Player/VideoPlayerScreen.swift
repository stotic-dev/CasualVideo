//
//  VideoPlayerScreen.swift
//  Library
//
//  一覧から選んだ動画を再生する再生画面（F-2）。
//
//  Screen と presentational View の分離方針は docs/swiftui.md を参照。
//  - Screen（VideoPlayerScreen）: Repository から再生リソース（AVPlayerItem）を取得する副作用を担う。
//    サムネイルと同様、再生リソースは Store を介さず View が直接 Repository から取得する
//    （docs/architecture.md の Store 方針: UI/フレームワーク型を Store に持ち込まない）。
//  - View（VideoPlayerView）: 受け取った再生状態（VideoPlayerViewState）を表示するだけ。副作用を持たない。
//

import AVKit
import Core
import SwiftUI

/// 動画の全画面再生画面。一覧セルからの遷移先として用いる。
public struct VideoPlayerScreen: View {

    let asset: VideoAsset

    @Environment(\.videoLibraryRepository) private var repository
    @State private var state: VideoPlayerViewState = .loading

    public init(asset: VideoAsset) {
        self.asset = asset
    }

    public var body: some View {
        playerView
            .navigationTitle(navigationTitle)
            .task {
                // ライフサイクルに紐づく副作用（再生リソースの取得）は Screen 側に置く。
                await loadPlayerItem()
            }
    }

    private var playerView: some View {
        let view = VideoPlayerView(state: state)
        #if os(iOS)
        return view.navigationBarTitleDisplayMode(.inline)
        #else
        return view
        #endif
    }

    private var navigationTitle: String {
        guard let date = asset.creationDate else { return "再生" }
        return date.formatted(.dateTime.year().month().day())
    }

    /// 再生用 AVPlayerItem を取得し、AVPlayer を組み立てて再生を開始する。
    private func loadPlayerItem() async {
        // 既に準備済みなら再取得しない（再表示時の作り直し防止）。
        if case .ready = state { return }

        guard let item = await repository.loadPlayerItem(asset.id) else {
            state = .failed
            return
        }
        let player = AVPlayer(playerItem: item)
        state = .ready(player)
        // ラフに「とりあえず流す」体験のため、表示と同時に自動再生する。
        player.play()
    }
}

/// 再生画面の presentational View。init で受け取った再生状態を表示するだけで副作用を持たない。
struct VideoPlayerView: View {

    let state: VideoPlayerViewState

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .tint(.white)

        case .ready(let player):
            VideoPlayer(player: player)

        case .failed:
            ContentUnavailableView(
                "再生できません",
                systemImage: "exclamationmark.triangle",
                description: Text("この動画を読み込めませんでした。")
            )
        }
    }
}
