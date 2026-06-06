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

import Core
import SwiftUI

/// プレイリストの全画面連続再生画面。一覧セルからの遷移先として用いる。
public struct VideoPlayerScreen: View {

    /// 連続再生の対象プレイリスト。
    let playlist: [VideoAsset]

    /// 再生を開始するインデックス。
    let startIndex: Int

    @Environment(\.videoPlayerProxy) private var playerProxy

    /// 再生リソースの読み込み状態（描画面のバインドは Proxy 経由で行うため、状態は進行のみを表す）。
    @State private var state: VideoPlayerViewState = .loading

    /// 連続再生の進行を管理する Store。再生画面のライフサイクルに紐づくため View 層で生成・保持する。
    @State private var playlistStore: PlaylistStore?

    /// 再生コントロールの表示・非表示と自動非表示タイマーを管理するドメインモデル。
    /// 表示制御ロジックは View に持たせず、このモデルへ委譲する。
    @State private var controlsVisibility = PlaybackControlsVisibility()

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
            isPlaying: playlistStore?.isPlaying ?? false,
            isPreparingItem: playlistStore?.isPreparingItem ?? false,
            playbackOrder: playlistStore?.playbackOrder ?? .sequential,
            repeatMode: playlistStore?.repeatMode ?? .off,
            areControlsVisible: controlsVisibility.isVisible,
            onToggleControls: { controlsVisibility.toggle() },
            onTogglePlayPause: { playlistStore?.togglePlayPause() },
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
    /// Store へ連続再生を委譲し、読み込み状態を更新する。描画面のバインドは CustomVideoPlayer が Proxy 経由で行う。
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

        // 再生開始できたか（=対象アセットが選択できたか）で readiness を判定する。
        // 描画用の AVPlayer は取り出さず、CustomVideoPlayer が Proxy 経由で描画面を構成する。
        state = store.currentAsset == nil ? .failed : .ready

        // 読み込み完了（.ready）時はコントロールを表示し、自動非表示タイマーを開始する。
        if case .ready = state {
            controlsVisibility.show()
        }
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
    /// 現在再生中かどうか（再生/一時停止ボタンの表示切り替えに用いる）。
    let isPlaying: Bool
    /// PlayerItem セットアップ中かどうか。true の間はコントロールを非活性化しインジケーターを表示する。
    let isPreparingItem: Bool
    let playbackOrder: PlaybackOrder
    let repeatMode: RepeatMode
    /// 再生コントロールを表示中かどうか。タップでトグルされ、一定時間後に自動で非表示になる。
    let areControlsVisible: Bool
    /// 画面タップによるコントロール表示・非表示のトグル。
    let onToggleControls: () -> Void
    let onTogglePlayPause: () -> Void
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

        case .ready:
            CustomVideoPlayer()
                // 画面タップでコントロールの表示・非表示をトグルする。
                .contentShape(.rect)
                .onTapGesture { onToggleControls() }
                .overlay(alignment: .top) {
                    if totalCount > 1, let position, areControlsVisible {
                        Text("\(position) / \(totalCount)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottom) {
                    if totalCount > 1, areControlsVisible {
                        playbackControls
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: areControlsVisible)

        case .failed:
            ContentUnavailableView(
                "再生できません",
                systemImage: "exclamationmark.triangle",
                description: Text("この動画を読み込めませんでした。")
            )
        }
    }

    private var playbackControls: some View {
        VStack(spacing: .zero) {
            Spacer()
            HStack(spacing: 32) {
                playerControlButton {
                    Image(systemName: "backward.fill")
                } action: {
                    Task { await onPlayPrevious() }
                }
                .disabled(!canPlayPrevious)
                .foregroundStyle(.white)

                // 再生 / 一時停止。セットアップ中はインジケーターへ差し替える。
                playPauseControl

                playerControlButton {
                    Image(systemName: "forward.fill")
                } action: {
                    Task { await onPlayNext() }
                }
                .disabled(!canPlayNext)
                .foregroundStyle(.white)
            }
            Spacer()
            HStack(spacing: 32) {
                Spacer()
                // シャッフル切り替え（F-5）。有効時はアクセントカラーで状態を示す。
                playerControlButton {
                    Image(systemName: "shuffle")
                } action: {
                    onToggleShuffle()
                }
                .foregroundStyle(playbackOrder == .shuffle ? Color.accentColor : .white)
                // リピート切り替え（F-5: off → all → one → off）。off 以外でアクセントカラー、one は 1 を示すシンボル。
                playerControlButton {
                    Image(systemName: repeatSymbolName)
                } action: {
                    onCycleRepeat()
                }
                .foregroundStyle(repeatMode == .off ? Color.white : Color.accentColor)
            }
            Spacer()
                .frame(height: 24)
        }
        .padding(.horizontal, 32)
        .font(.title)
        // PlayerItem セットアップ中はコントロール全体を非活性化する。
        .disabled(isPreparingItem)
    }

    /// 再生 / 一時停止ボタン。セットアップ中はインジケーターを表示する。
    @ViewBuilder
    private var playPauseControl: some View {
        if isPreparingItem {
            ProgressView()
                .tint(.white)
        } else {
            playerControlButton {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            } action: {
                onTogglePlayPause()
            }
            .foregroundStyle(.white)
        }
    }
    
    private func playerControlButton(content: () -> some View, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            content()
                .padding(8)
        }
    }

    /// リピートモードに対応する SF Symbol 名。
    private var repeatSymbolName: String {
        switch repeatMode {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }
}

#if DEBUG

// MARK: - Preview

/// 任意の状態を再現できるよう、presentational な `VideoPlayerView` を直接組み立てる Preview ヘルパー。
///
/// 再生エンジンは Preview で動作しないため、`CustomVideoPlayer` がモックアップへ切り替わるよう
/// `.environment(\.isPreview, true)` を注入する。
@MainActor
private func previewVideoPlayerView(
    state: VideoPlayerViewState = .ready,
    position: Int? = 2,
    totalCount: Int = 5,
    isPlaying: Bool = true,
    isPreparingItem: Bool = false,
    playbackOrder: PlaybackOrder = .sequential,
    repeatMode: RepeatMode = .off,
    areControlsVisible: Bool = true
) -> some View {
    VideoPlayerView(
        state: state,
        position: position,
        totalCount: totalCount,
        canPlayNext: true,
        canPlayPrevious: true,
        isPlaying: isPlaying,
        isPreparingItem: isPreparingItem,
        playbackOrder: playbackOrder,
        repeatMode: repeatMode,
        areControlsVisible: areControlsVisible,
        onToggleControls: {},
        onTogglePlayPause: {},
        onPlayNext: {},
        onPlayPrevious: {},
        onToggleShuffle: {},
        onCycleRepeat: {}
    )
    .environment(\.isPreview, true)
}

#Preview("再生中") {
    previewVideoPlayerView(isPlaying: true)
}

#Preview("一時停止中") {
    previewVideoPlayerView(isPlaying: false)
}

#Preview("セットアップ中") {
    previewVideoPlayerView(isPreparingItem: true)
}

#Preview("シャッフル + 全体リピート") {
    previewVideoPlayerView(playbackOrder: .shuffle, repeatMode: .all)
}

#Preview("コントロール非表示") {
    previewVideoPlayerView(areControlsVisible: false)
}

#Preview("読み込み中") {
    previewVideoPlayerView(state: .loading)
}

#Preview("再生失敗") {
    previewVideoPlayerView(state: .failed)
}

#endif
