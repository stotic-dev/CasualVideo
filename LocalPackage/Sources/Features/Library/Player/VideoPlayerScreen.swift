//
//  VideoPlayerScreen.swift
//  Library
//
//  一覧から選んだ動画を起点に、一覧全体をプレイリストとして連続再生する再生画面（F-2 / F-4 / F-5）。
//
//  Screen と presentational View の分離方針は docs/swiftui.md を参照。
//  - Screen（VideoPlayerScreen）: 再生エンジンの操作（VideoPlayerProxy / PlaylistStore 経由）と副作用を担う。
//    AVPlayer / AVPlayerItem を View 内で直接生成・操作せず、すべて Proxy / Store へ委譲する。
//  - View（VideoPlayerView）: 受け取った再生状態（VideoPlayerViewState）と操作クロージャを表示するだけ。副作用を持たない。
//
//  連続再生（F-4）の進行管理（現在位置・次/前送り・再生終了での自動遷移）と
//  シャッフル / リピート（F-5）の状態管理は Core の PlaylistStore が担う。
//

import AVFoundation
import Core
import SwiftUI

/// プレイリストの全画面連続再生画面。一覧セルからの遷移先として用いる。
public struct VideoPlayerScreen: View {

    /// 連続再生の対象プレイリスト。
    let playlist: [VideoAsset]

    /// 再生を開始するインデックス。
    let startIndex: Int

    @Environment(\.videoPlayerProxy) private var playerProxy

    /// 再生リソースの表示状態（AVPlayer は View ライフサイクルに紐づくため View 層で保持）。
    @State private var state: VideoPlayerViewState = .loading

    /// 連続再生の進行を管理する Store。再生画面のライフサイクルに紐づくため View 層で生成・保持する。
    @State private var playlistStore: PlaylistStore?

    public init(playlist: [VideoAsset], startIndex: Int = 0) {
        self.playlist = playlist
        self.startIndex = startIndex
    }

    public var body: some View {
        playerView
            .navigationTitle(navigationTitle)
            .task {
                // ライフサイクルに紐づく副作用（読み込み・連続再生開始）は Screen 側に置く。
                await onAppear()
            }
    }

    private var playerView: some View {
        let view = VideoPlayerView(
            state: state,
            position: playlistStore?.currentPosition,
            totalCount: playlistStore?.totalCount ?? 0,
            canPlayNext: playlistStore?.canPlayNext ?? false,
            canPlayPrevious: playlistStore?.canPlayPrevious ?? false,
            playbackOrder: playlistStore?.playbackOrder ?? .sequential,
            repeatMode: playlistStore?.repeatMode ?? .off,
            onPlayNext: { await playlistStore?.playNext() },
            onPlayPrevious: { await playlistStore?.playPrevious() },
            onToggleShuffle: { playlistStore?.toggleShuffle() },
            onCycleRepeat: { playlistStore?.cycleRepeatMode() }
        )
        #if os(iOS)
        return view.navigationBarTitleDisplayMode(.inline)
        #else
        return view
        #endif
    }

    private var navigationTitle: String {
        guard let date = playlistStore?.currentAsset?.creationDate else { return "再生" }
        return date.formatted(.dateTime.year().month().day())
    }
}

private extension VideoPlayerScreen {
    /// Store へ連続再生を委譲し、描画用の AVPlayer を受け取って表示状態を更新する。
    func onAppear() async {
        // 既に準備済みなら作り直さない（再表示時の二重ロード防止）。
        if case .ready = state { return }
        guard !playlist.isEmpty else {
            state = .failed
            return
        }

        // PIP・バックグラウンド再生（F-3）のためのオーディオセッションを再生前に構成する。
        playerProxy.prepareForBackgroundPlayback()

        let store = PlaylistStore(playerProxy: playerProxy)
        playlistStore = store
        await store.start(playlist: playlist, from: startIndex)

        guard let player = playerProxy.player() else {
            state = .failed
            return
        }
        // player は描画（AVPlayerLayer へのバインド）にのみ使う。操作は Proxy / Store 経由。
        state = .ready(player)
    }
}

/// 再生画面の presentational View。init で受け取った状態・操作クロージャを表示するだけで副作用を持たない。
struct VideoPlayerView: View {

    let state: VideoPlayerViewState
    /// 現在の再生位置（1 始まり）。プレイリストが 1 件以下なら nil で非表示。
    let position: Int?
    let totalCount: Int
    let canPlayNext: Bool
    let canPlayPrevious: Bool
    let playbackOrder: PlaybackOrder
    let repeatMode: RepeatMode
    let onPlayNext: () async -> Void
    let onPlayPrevious: () async -> Void
    let onToggleShuffle: () -> Void
    let onCycleRepeat: () -> Void

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
                .overlay(alignment: .top) {
                    if totalCount > 1, let position {
                        Text("\(position) / \(totalCount)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottom) {
                    if totalCount > 1 {
                        playbackControls
                    }
                }

        case .failed:
            ContentUnavailableView(
                "再生できません",
                systemImage: "exclamationmark.triangle",
                description: Text("この動画を読み込めませんでした。")
            )
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 32) {
            // シャッフル切り替え（F-5）。有効時はアクセントカラーで状態を示す。
            Button {
                onToggleShuffle()
            } label: {
                Image(systemName: "shuffle")
            }
            .foregroundStyle(playbackOrder == .shuffle ? Color.accentColor : .white)

            Button {
                Task { await onPlayPrevious() }
            } label: {
                Image(systemName: "backward.fill")
            }
            .disabled(!canPlayPrevious)
            .foregroundStyle(.white)

            Button {
                Task { await onPlayNext() }
            } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(!canPlayNext)
            .foregroundStyle(.white)

            // リピート切り替え（F-5: off → all → one → off）。off 以外でアクセントカラー、one は 1 を示すシンボル。
            Button {
                onCycleRepeat()
            } label: {
                Image(systemName: repeatSymbolName)
            }
            .foregroundStyle(repeatMode == .off ? Color.white : Color.accentColor)
        }
        .font(.title)
        .padding()
    }

    /// リピートモードに対応する SF Symbol 名。
    private var repeatSymbolName: String {
        switch repeatMode {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }
}
