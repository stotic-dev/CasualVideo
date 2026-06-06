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