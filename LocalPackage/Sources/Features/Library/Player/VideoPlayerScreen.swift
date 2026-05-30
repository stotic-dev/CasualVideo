//
//  VideoPlayerScreen.swift
//  Library
//
//  一覧から選んだ動画を再生する再生画面（F-2）。
//
//  Screen と presentational View の分離方針は docs/swiftui.md を参照。
//  - Screen（VideoPlayerScreen）: 再生エンジンの操作（VideoPlayerProxy 経由）と、その副作用を担う。
//    AVPlayer / AVPlayerItem を View 内で直接生成・操作せず、すべて Proxy へ委譲する
//    （操作の責務は Infra の VideoPlayerClient に閉じ、UI 表示と分離する）。
//  - View（VideoPlayerView）: 受け取った再生状態（VideoPlayerViewState）を表示するだけ。副作用を持たない。
//

import AVFoundation
import Core
import SwiftUI

/// 動画の全画面再生画面。一覧セルからの遷移先として用いる。
public struct VideoPlayerScreen: View {

    let asset: VideoAsset

    @Environment(\.videoPlayerProxy) private var playerProxy
    @State private var state: VideoPlayerViewState = .loading

    public init(asset: VideoAsset) {
        self.asset = asset
    }

    public var body: some View {
        playerView
            .navigationTitle(navigationTitle)
            .task {
                // ライフサイクルに紐づく副作用（読み込み・再生開始）は Screen 側に置く。
                await start()
            }
            .onDisappear {
                // 画面を離れたら再生を止める（操作は Proxy 経由）。
                playerProxy.pause()
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

    /// Proxy へ読み込み・再生を委譲し、描画用の AVPlayer を受け取って表示状態を更新する。
    private func start() async {
        // 既に準備済みなら作り直さない（再表示時の二重ロード防止）。
        if case .ready = state { return }

        // ラフに「とりあえず流す」体験のため、読み込みと同時に自動再生する。
        let didLoad = await playerProxy.loadAndPlay(asset.id)
        guard didLoad, let player = playerProxy.player() else {
            state = .failed
            return
        }
        // player は描画（AVPlayerLayer へのバインド）にのみ使う。操作は Proxy 経由。
        state = .ready(player)
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
            CustomVideoPlayer(player: player)

        case .failed:
            ContentUnavailableView(
                "再生できません",
                systemImage: "exclamationmark.triangle",
                description: Text("この動画を読み込めませんでした。")
            )
        }
    }
}
