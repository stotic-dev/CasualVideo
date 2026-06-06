//
//  PlayerControlsContent.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/06.
//

import SwiftUI
import Core

struct PlayerControlsContent: View {
    let progress: PlaybackProgress
    let playbackOrder: PlaybackOrder
    let repeatMode: RepeatMode
    let canPlayPrevious: Bool
    let canPlayNext: Bool
    let isPreparingItem: Bool
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void
    let onPlayPrevious: () async -> Void
    let onPlayNext: () async -> Void
    let onToggleShuffle: () -> Void
    let onCycleRepeat: () -> Void
    let onTogglePlayPause: () -> Void
    
    var body: some View {
        ZStack {
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
            VStack(spacing: 24) {
                // シーク操作・残り時間表示（F-6）。シーク可能な長さがあるときのみ表示する。
                if progress.isSeekable {
                    SeekBar(progress: progress, onSeek: onSeek)
                        .padding(.bottom, 8)
                }
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
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(.horizontal, 32)
        .font(.title)
        // PlayerItem セットアップ中はコントロール全体を非活性化する。
        .disabled(isPreparingItem)
    }
}

private extension PlayerControlsContent {
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

/// 任意の状態を再現できるよう、presentational な `PlayerControlsContent` を直接組み立てる Preview ヘルパー。
@MainActor
private func previewPlayerControlsContent(
    isPlaying: Bool = true,
    isPreparingItem: Bool = false,
    playbackOrder: PlaybackOrder = .sequential,
    repeatMode: RepeatMode = .off,
    progress: PlaybackProgress = PlaybackProgress(currentTime: 42, duration: 215)
) -> some View {
    PlayerControlsContent(
        progress: progress,
        playbackOrder: playbackOrder,
        repeatMode: repeatMode,
        canPlayPrevious: true,
        canPlayNext: true,
        isPreparingItem: isPreparingItem,
        isPlaying: isPlaying,
        onSeek: { _ in },
        onPlayPrevious: {},
        onPlayNext: {},
        onToggleShuffle: {},
        onCycleRepeat: {},
        onTogglePlayPause: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
}

#Preview("再生中") {
    previewPlayerControlsContent(isPlaying: true)
}

#Preview("一時停止中") {
    previewPlayerControlsContent(isPlaying: false)
}

#Preview("セットアップ中") {
    previewPlayerControlsContent(isPreparingItem: true)
}

#Preview("シャッフル + 全体リピート") {
    previewPlayerControlsContent(playbackOrder: .shuffle, repeatMode: .all)
}

#Preview("シーク不可（長さ未確定）") {
    previewPlayerControlsContent(progress: PlaybackProgress(currentTime: 0, duration: 0))
}

#endif
