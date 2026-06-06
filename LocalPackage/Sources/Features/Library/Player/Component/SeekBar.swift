//
//  SeekBar.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/06.
//

import SwiftUI
import Core

/// 再生位置のシークと経過 / 全体時間を表示する presentational なシークバー（F-6）。
///
/// ドラッグ中は内部の一時値（`editingSeconds`）でつまみ位置を即時追従させ、操作中は外部の進捗更新で
/// つまみが揺れないようにする。ドラッグ終了時に `onSeek` で確定位置を親へ伝える。
struct SeekBar: View {

    /// 現在の再生進捗（経過時間・総再生時間）。
    let progress: PlaybackProgress
    /// 指定秒へのシークを親へ伝えるクロージャ。
    let onSeek: (TimeInterval) -> Void

    /// ドラッグ操作中の一時的な秒数。非ドラッグ時は nil で `progress` に追従する。
    @State private var editingSeconds: TimeInterval?

    var body: some View {
        VStack(spacing: 4) {
            slider
            Text("\(Self.format(displaySeconds)) / \(Self.format(progress.duration))")
                .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview("SeekBar_再生位置_0", traits: .sizeThatFitsLayout) {
    SeekBar(
        progress: .init(currentTime: 0, duration: 3000),
        onSeek: { _ in }
    )
    .padding(16)
    .background(.black)
}

#Preview("SeekBar_再生位置_真ん中", traits: .sizeThatFitsLayout) {
    SeekBar(
        progress: .init(currentTime: 1500, duration: 3000),
        onSeek: { _ in }
    )
    .padding(16)
    .background(.black)
}

#Preview("SeekBar_再生位置_終わり", traits: .sizeThatFitsLayout) {
    SeekBar(
        progress: .init(currentTime: 3000, duration: 3000),
        onSeek: { _ in }
    )
    .padding(16)
    .background(.black)
}
