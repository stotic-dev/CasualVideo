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

/// プレイリストの全画面連続再生画面。一覧セルからの遷移先として用いる。
public struct VideoPlayerScreen: View {

    /// 連続再生の対象プレイリストを供給するプロバイダ。
    ///
    /// 固定一覧（全動画 / 手動選択）はそのまま返し、アルバム単位の場合は
    /// 再生開始時に最新のアルバム内容を取得して返す（F-6 動的取得）。
    let playlistProvider: () async -> [VideoAsset]

    /// 再生を開始するインデックス。
    let startIndex: Int

    @Environment(\.videoPlayerProxy) private var playerProxy
    @Environment(\.nowPlayingInfoProxy) private var nowPlayingInfoProxy
    @Environment(\.dismiss) var dismiss

    /// 再生リソースの読み込み状態（描画面のバインドは Proxy 経由で行うため、状態は進行のみを表す）。
    @State private var state: VideoPlayerViewState = .loading

    /// 連続再生の進行を管理する Store。再生画面のライフサイクルに紐づくため View 層で生成・保持する。
    @State private var playlistStore: PlaylistStore?

    /// 再生コントロールの表示・非表示と自動非表示タイマーを管理するドメインモデル。
    /// 表示制御ロジックは View に持たせず、このモデルへ委譲する。
    @State private var controlsVisibility = PlaybackControlsVisibility()
    
    @State var errorAlertStore = ErrorAlertStore()

    /// 固定のプレイリストで再生する（全動画 / 手動選択など、起動時点で確定する場合）。
    public init(playlist: [VideoAsset], startIndex: Int = 0) {
        self.playlistProvider = { playlist }
        self.startIndex = startIndex
    }

    /// 再生開始時にプレイリストを動的取得して再生する（アルバム単位 / F-6）。
    public init(startIndex: Int = 0, playlistProvider: @escaping () async -> [VideoAsset]) {
        self.playlistProvider = playlistProvider
        self.startIndex = startIndex
    }

    public var body: some View {
        playerView
            .navigationTitle(navigationTitle)
            .task {
                // ライフサイクルに紐づく副作用（読み込み・連続再生開始）は Screen 側に置く。
                await onAppear()
            }
            .onChange(of: playlistStore?.error) { _, newValue in
                onError(newValue)
            }
            .errorAlert(errorAlertStore) {
                onDismiss()
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
            progress: playlistStore?.progress ?? PlaybackProgress(),
            areControlsVisible: controlsVisibility.isVisible,
            onToggleControls: { controlsVisibility.toggle() },
            onTogglePlayPause: { playlistStore?.togglePlayPause() },
            onPlayNext: { await playlistStore?.playNext() },
            onPlayPrevious: { await playlistStore?.playPrevious() },
            onToggleShuffle: { playlistStore?.toggleShuffle() },
            onCycleRepeat: { playlistStore?.cycleRepeatMode() },
            onSeek: { playlistStore?.seek(to: $0) }
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

        // プレイリストを供給する（アルバム単位は最新内容を動的取得する / F-6）。
        let playlist = await playlistProvider()
        guard !playlist.isEmpty else {
            state = .failed
            return
        }

        // PIP・バックグラウンド再生（F-3）のためのオーディオセッションを再生前に構成する。
        playerProxy.prepareForBackgroundPlayback()

        let store = PlaylistStore(
            playerProxy: playerProxy,
            nowPlayingInfoProxy: nowPlayingInfoProxy
        )
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
    
    func onError(_ error: ErrorAlertItem?) {
        guard let error = error else { return }
        errorAlertStore.setItem(error)
    }
    
    func onDismiss() {
        dismiss()
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
    /// 現在再生中アイテムの再生進捗（シークバーの位置・長さ表示に用いる）。
    let progress: PlaybackProgress
    /// 再生コントロールを表示中かどうか。タップでトグルされ、一定時間後に自動で非表示になる。
    let areControlsVisible: Bool
    /// 画面タップによるコントロール表示・非表示のトグル。
    let onToggleControls: () -> Void
    let onTogglePlayPause: () -> Void
    let onPlayNext: () async -> Void
    let onPlayPrevious: () async -> Void
    let onToggleShuffle: () -> Void
    let onCycleRepeat: () -> Void
    /// シークバー操作による再生位置変更（指定秒へシーク）。
    let onSeek: (TimeInterval) -> Void

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
                    if totalCount >= 1, areControlsVisible {
                        PlayerControlsContent(
                            progress: progress,
                            playbackOrder: playbackOrder,
                            repeatMode: repeatMode,
                            canPlayPrevious: canPlayPrevious,
                            canPlayNext: canPlayNext,
                            isPreparingItem: isPreparingItem,
                            isPlaying: isPlaying,
                            onSeek: onSeek,
                            onPlayPrevious: onPlayPrevious,
                            onPlayNext: onPlayNext,
                            onToggleShuffle: onToggleShuffle,
                            onCycleRepeat: onCycleRepeat,
                            onTogglePlayPause: onTogglePlayPause
                        )
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
}

#if DEBUG
@MainActor
private func previewVideoPlayerView(
    state: VideoPlayerViewState = .ready,
    position: Int? = 2,
    totalCount: Int = 5,
    isPlaying: Bool = true,
    isPreparingItem: Bool = false,
    playbackOrder: PlaybackOrder = .sequential,
    repeatMode: RepeatMode = .off,
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
        progress: progress,
        areControlsVisible: areControlsVisible,
        onToggleControls: {},
        onTogglePlayPause: {},
        onPlayNext: {},
        onPlayPrevious: {},
        onToggleShuffle: {},
        onCycleRepeat: {},
        onSeek: { _ in }
    )
    .environment(\.isPreview, true)
}

#Preview {
    previewVideoPlayerView()
}

#endif
