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
        VStack(spacing: .zero) {
            Spacer()
            // シーク操作・残り時間表示（F-6）。シーク可能な長さがあるときのみ表示する。
            if progress.isSeekable {
                SeekBar(progress: progress, onSeek: onSeek)
                    .padding(.bottom, 8)
            }
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

/// 再生位置のシークと経過 / 全体時間を表示する presentational なシークバー（F-6）。
///
/// ドラッグ中は内部の一時値（`editingSeconds`）でつまみ位置を即時追従させ、操作中は外部の進捗更新で
/// つまみが揺れないようにする。ドラッグ終了時に `onSeek` で確定位置を親へ伝える。
private struct SeekBar: View {

    /// 現在の再生進捗（経過時間・総再生時間）。
    let progress: PlaybackProgress
    /// 指定秒へのシークを親へ伝えるクロージャ。
    let onSeek: (TimeInterval) -> Void

    /// ドラッグ操作中の一時的な秒数。非ドラッグ時は nil で `progress` に追従する。
    @State private var editingSeconds: TimeInterval?

    var body: some View {
        VStack(spacing: 4) {
            slider
            HStack {
                Text(Self.format(displaySeconds))
                Spacer()
                Text(Self.format(progress.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)
        }
    }

    /// 表示・つまみ位置に使う秒数（ドラッグ中は一時値、それ以外は実進捗）。
    private var displaySeconds: TimeInterval {
        editingSeconds ?? progress.currentTime
    }

    private var slider: some View {
        Slider(
            value: Binding(
                get: { displaySeconds },
                set: { editingSeconds = $0 }
            ),
            in: 0...max(progress.duration, 0.1)
        ) { isEditing in
            // ドラッグ終了時に確定位置でシークし、一時値を解除して実進捗に戻す。
            if !isEditing {
                if let editingSeconds {
                    onSeek(editingSeconds)
                }
                editingSeconds = nil
            }
        }
        .tint(.white)
    }

    /// 秒数を mm:ss（1 時間以上は h:mm:ss）形式へ整形する。
    private static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
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
