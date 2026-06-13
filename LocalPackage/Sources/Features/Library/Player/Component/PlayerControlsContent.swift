//
//  PlayerControlsContent.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/06.
//

import SwiftUI
import Core

struct PlayerControlsContent: View {
    @Environment(\.castComponentResolver) var castComponentResolver
    
    let progress: PlaybackProgress
    let playbackOrder: PlaybackOrder
    let repeatMode: RepeatMode
    let canPlayPrevious: Bool
    let canPlayNext: Bool
    let isPreparingItem: Bool
    let isPlaying: Bool
    /// 音声ミュート中かどうか（F-7）。
    let isMuted: Bool
    /// 現在の再生速度（F-7）。
    let playbackRate: PlaybackRate
    let onClose: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onPlayPrevious: () async -> Void
    let onPlayNext: () async -> Void
    let onToggleShuffle: () -> Void
    let onCycleRepeat: () -> Void
    let onTogglePlayPause: () -> Void
    /// ミュート切り替え（F-7）。
    let onToggleMute: () -> Void
    /// 再生速度選択（F-7）。
    let onSelectRate: (PlaybackRate) -> Void
    /// PIP（ピクチャ・イン・ピクチャ）へ遷移する（F-3）。タップで再生画面を閉じ、PIP 小窓へ移行する。
    let onStartPictureInPicture: () -> Void

    var body: some View {
        // 近接する Liquid Glass ボタン同士をブレンド・最適化するためコンテナで囲う。
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                controls
            }
        } else {
            controls
        }
    }

    private var controls: some View {
        ZStack {
            headerControl
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            centerControl
            bottomControl
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(.horizontal, 32)
        .font(.title)
        // PlayerItem セットアップ中はコントロール全体を非活性化する。
        .disabled(isPreparingItem)
    }
}

private extension PlayerControlsContent {
    var headerControl: some View {
        HStack(spacing: .zero) {
            playerControlButton {
                Image(systemName: "xmark")
            } action: {
                onClose()
            }
            Spacer()
            HStack(spacing: 8) {
                castComponentResolver()
                    .padding(8)
                    .glassEffectStyle()
                // PIP へ遷移（F-3）。再生画面を閉じて PIP 小窓へ移行する。
                playerControlButton {
                    Image(systemName: "pip.enter")
                } action: {
                    onStartPictureInPicture()
                }
            }
        }
        .foregroundStyle(.white)
    }
    
    var centerControl: some View {
        HStack(spacing: .zero) {
            playerControlButton {
                Image(systemName: "backward.fill")
            } action: {
                Task { await onPlayPrevious() }
            }
            .disabled(!canPlayPrevious)
            .foregroundStyle(.white)
            Spacer()
            // 再生 / 一時停止。セットアップ中はインジケーターへ差し替える。
            playPauseControl
            Spacer()
            playerControlButton {
                Image(systemName: "forward.fill")
            } action: {
                Task { await onPlayNext() }
            }
            .disabled(!canPlayNext)
            .foregroundStyle(.white)
        }
    }
    
    var bottomControl: some View {
        VStack(spacing: 24) {
            // シーク操作・残り時間表示（F-6）。シーク可能な長さがあるときのみ表示する。
            if progress.isSeekable {
                SeekBar(progress: progress, onSeek: onSeek)
                    .padding(.bottom, 8)
            }
            HStack(spacing: 16) {
                Spacer()
                // ミュート切り替え（F-7）。ミュート時はアクセントカラーで状態を示す。
                playerControlButton {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                } action: {
                    onToggleMute()
                }
                .foregroundStyle(isMuted ? Color.accentColor : .white)

                // 再生速度選択（F-7）。現在の速度をラベルに表示し、Menu から選択する。
                rateMenu

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
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
    
    /// 再生 / 一時停止ボタン。セットアップ中はインジケーターを表示する。
    @ViewBuilder
    var playPauseControl: some View {
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
    
    /// 再生速度選択 Menu（F-7）。ラベルは現在の速度、項目は全速度で選択中にチェックを付ける。
    private var rateMenu: some View {
        Menu {
            ForEach(PlaybackRate.allCases) { rate in
                Button {
                    onSelectRate(rate)
                } label: {
                    if rate == playbackRate {
                        Label(rate.displayName, systemImage: "checkmark")
                    } else {
                        Text(rate.displayName)
                    }
                }
            }
        } label: {
            Text(playbackRate.displayName)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(8)
        }
        // 速度選択 Menu も他のボタンと揃えて Liquid Glass を与える。
        .glassButtonStyle()
    }

    private func playerControlButton(content: () -> some View, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            content()
                .frame(width: 12, height: 12)
                .padding(8)
        }
        // コントロールの各ボタンに Liquid Glass を与える（iOS 26 / macOS 26）。
        .glassButtonStyle()
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
    isMuted: Bool = false,
    playbackRate: PlaybackRate = .normal,
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
        isMuted: isMuted,
        playbackRate: playbackRate,
        onClose: {},
        onSeek: { _ in },
        onPlayPrevious: {},
        onPlayNext: {},
        onToggleShuffle: {},
        onCycleRepeat: {},
        onTogglePlayPause: {},
        onToggleMute: {},
        onSelectRate: { _ in },
        onStartPictureInPicture: {}
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

#Preview("ミュート + 2.0x") {
    previewPlayerControlsContent(isMuted: true, playbackRate: .double)
}

#endif
