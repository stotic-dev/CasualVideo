//
//  VideoPlayerScreen.swift
//  Library
//
//  一覧から選んだ動画を起点に、一覧全体をプレイリストとして連続再生する再生画面（F-2 / F-4 / F-5）。
//
//  Screen と presentational View の分離方針は docs-internal/swiftui.md を参照。
//  - Screen（VideoPlayerScreen）: 再生エンジンの操作（VideoPlayerProxy / PlaylistStore 経由）と副作用を担う。
//    AVPlayer / AVPlayerItem を View 内で直接生成・操作せず、すべて Proxy / Store へ委譲する。
//  - View（VideoPlayerView）: 受け取った再生状態（VideoPlayerViewState）と操作クロージャを表示するだけ。副作用を持たない。
//
//  連続再生（F-4）の進行管理（現在位置・次/前送り・再生終了での自動遷移）と
//  シャッフル / リピート（F-5）の状態管理は Core の PlaylistStore が担う。
//

import Core
import SwiftUI

/// プレイリストの全画面連続再生画面。`PlaybackStore` が保持する再生セッションを表示する。
///
/// 再生セッション（`PlaylistStore`）はアプリスコープの `PlaybackStore` が保持するため、
/// この画面は提示・非提示（PIP への移行と復帰を含む）で破棄・再生成されても再生状態を失わない。
/// 画面自体は副作用の起点を持たず、Store の状態を表示し操作を委譲するだけに留める。
struct VideoPlayerScreen: View {

    @Environment(PlaybackStore.self) private var playbackStore

    /// 再生コントロールの表示・非表示と自動非表示タイマーを管理するドメインモデル。
    /// 表示制御ロジックは View に持たせず、このモデルへ委譲する。
    @State private var controlsVisibility = PlaybackControlsVisibility()

    @State private var errorAlertStore = ErrorAlertStore()

    var body: some View {
        playerView
            .task {
                // 提示のたび（PIP からの復帰を含む）に、再生可能ならコントロールを表示する。
                if state.isReady {
                    controlsVisibility.show()
                }
            }
            .onChange(of: state) { _, newValue in
                // 再生可能になった時（読み込み完了・キャスト切替）にコントロールを表示し、
                // 自動非表示タイマーを開始する。
                if newValue.isReady {
                    controlsVisibility.show()
                }
            }
            .onChange(of: store.error) { _, newValue in
                onError(newValue)
            }
            .errorAlert(errorAlertStore) {
                // エラー時の閉じる導線でも再生を残さず、セッションを完全停止・破棄する。
                playbackStore.stop()
            }
    }

    /// 現在の連続再生 Store（`PlaybackStore` が保持する単一インスタンス。常に非 nil）。
    private var store: PlaylistStore { playbackStore.playlistStore }

    /// 進行状態とキャスト有無から導出した、画面が分岐すべき表示状態。
    /// 写像ロジックは `VideoPlayerViewState` 側に閉じる。
    private var state: VideoPlayerViewState {
        VideoPlayerViewState(phase: playbackStore.phase, isCasting: playbackStore.isCasting)
    }

    private var playerView: some View {
        VideoPlayerView(
            state: state,
            position: store.currentPosition,
            totalCount: store.totalCount,
            canPlayNext: store.canPlayNext,
            canPlayPrevious: store.canPlayPrevious,
            isPlaying: store.isPlaying,
            isPreparingItem: store.isPreparingItem,
            playbackOrder: store.playbackOrder,
            repeatMode: store.repeatMode,
            isMuted: store.isMuted,
            playbackRate: store.playbackRate,
            progress: store.progress,
            areControlsVisible: controlsVisibility.isVisible,
            onClose: { playbackStore.stop() },
            onToggleControls: { controlsVisibility.toggle() },
            onTogglePlayPause: { store.togglePlayPause() },
            onPlayNext: { await store.playNext() },
            onPlayPrevious: { await store.playPrevious() },
            onToggleShuffle: { store.toggleShuffle() },
            onCycleRepeat: { store.cycleRepeatMode() },
            onSeek: { store.seek(to: $0) },
            onToggleMute: { store.toggleMute() },
            onSelectRate: { store.setPlaybackRate($0) },
            // PIP（F-3）へ移行する。Store が開始完了を待って全画面プレイヤーを閉じる。
            onStartPictureInPicture: { playbackStore.enterPictureInPicture() }
        )
    }

    private var navigationTitle: String {
        guard let date = store.currentAsset?.creationDate else { return "再生" }
        return date.formatted(.dateTime.year().month().day())
    }
}

private extension VideoPlayerScreen {
    func onError(_ error: ErrorAlertItem?) {
        guard let error else { return }
        errorAlertStore.setItem(error)
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
    /// 音声ミュート中かどうか（F-7）。
    let isMuted: Bool
    /// 現在の再生速度（F-7）。
    let playbackRate: PlaybackRate
    /// 現在再生中アイテムの再生進捗（シークバーの位置・長さ表示に用いる）。
    let progress: PlaybackProgress
    /// 再生コントロールを表示中かどうか。タップでトグルされ、一定時間後に自動で非表示になる。
    let areControlsVisible: Bool
    /// プレイヤー画面を閉じる
    let onClose: () -> Void
    /// 画面タップによるコントロール表示・非表示のトグル。
    let onToggleControls: () -> Void
    let onTogglePlayPause: () -> Void
    let onPlayNext: () async -> Void
    let onPlayPrevious: () async -> Void
    let onToggleShuffle: () -> Void
    let onCycleRepeat: () -> Void
    /// シークバー操作による再生位置変更（指定秒へシーク）。
    let onSeek: (TimeInterval) -> Void
    /// ミュート切り替え（F-7）。
    let onToggleMute: () -> Void
    /// 再生速度選択（F-7）。
    let onSelectRate: (PlaybackRate) -> Void
    /// PIP へ遷移する（F-3）。タップで再生画面を閉じ、PIP 小窓へ移行する。
    let onStartPictureInPicture: () -> Void

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

        case .playing, .casting:
            playerSurface

        case .failed:
            ContentUnavailableView(
                "再生できません",
                systemImage: "exclamationmark.triangle",
                description: Text("この動画を読み込めませんでした。")
            )
        }
    }

    /// 再生中（ローカル / キャスト）の映像面とコントロール群。
    private var playerSurface: some View {
        videoLayer
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
                if totalCount >= 1, areControlsVisible {
                    PlayerControlsContent(
                        progress: progress,
                        playbackOrder: playbackOrder,
                        repeatMode: repeatMode,
                        canPlayPrevious: canPlayPrevious,
                        canPlayNext: canPlayNext,
                        isPreparingItem: isPreparingItem,
                        isPlaying: isPlaying,
                        isMuted: isMuted,
                        playbackRate: playbackRate,
                        isPictureInPictureEnabled: state.allowsPictureInPicture,
                        onClose: onClose,
                        onSeek: onSeek,
                        onPlayPrevious: onPlayPrevious,
                        onPlayNext: onPlayNext,
                        onToggleShuffle: onToggleShuffle,
                        onCycleRepeat: onCycleRepeat,
                        onTogglePlayPause: onTogglePlayPause,
                        onToggleMute: onToggleMute,
                        onSelectRate: onSelectRate,
                        onStartPictureInPicture: onStartPictureInPicture
                    )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: areControlsVisible)
    }

    /// 映像面。キャスト中は端末での再生を止め「Cast 再生中」表示へ差し替える。
    @ViewBuilder
    private var videoLayer: some View {
        switch state {
        case .casting:
            castingIndicator
        default:
            CustomVideoPlayer()
        }
    }

    /// キャスト中に映像面へ表示する「Chromecast で再生中」インジケーター。
    private var castingIndicator: some View {
        VStack(spacing: 16) {
            Image(systemName: "tv.and.hifispeaker.fill")
                .font(.system(size: 56))
            Text("Chromecast で再生中")
                .font(.headline)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
@MainActor
private func previewVideoPlayerView(
    state: VideoPlayerViewState = .playing,
    position: Int? = 2,
    totalCount: Int = 5,
    isPlaying: Bool = true,
    isPreparingItem: Bool = false,
    playbackOrder: PlaybackOrder = .sequential,
    repeatMode: RepeatMode = .off,
    isMuted: Bool = false,
    playbackRate: PlaybackRate = .normal,
    progress: PlaybackProgress = PlaybackProgress(currentTime: 42, duration: 215),
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
        isMuted: isMuted,
        playbackRate: playbackRate,
        progress: progress,
        areControlsVisible: areControlsVisible,
        onClose: {},
        onToggleControls: {},
        onTogglePlayPause: {},
        onPlayNext: {},
        onPlayPrevious: {},
        onToggleShuffle: {},
        onCycleRepeat: {},
        onSeek: { _ in },
        onToggleMute: {},
        onSelectRate: { _ in },
        onStartPictureInPicture: {}
    )
    .environment(\.isPreview, true)
}

#Preview {
    previewVideoPlayerView()
}

#Preview("Cast 再生中") {
    previewVideoPlayerView(state: .casting)
}

#endif
