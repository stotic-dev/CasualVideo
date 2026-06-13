//
//  PlaybackControlsVisibility.swift
//  Library
//
//  再生コントロール（playbackControls）の表示・非表示状態と、その自動非表示ロジックを担うドメインモデル。
//

import Foundation
import Observation

/// 再生コントロールの表示・非表示を管理する Store。
///
/// 画面タップによる表示トグルと、表示状態になってから一定時間後に自動で非表示にするタイマーを内包する。
/// この「表示・非表示の状態とその遷移ロジック」をドメインとして切り出し、View 側で直接持たせない。
///
/// - Note: 表示状態という UI に近い概念だが、自動非表示タイマー等の振る舞いを含むためドメインモデルとして扱う。
///   SwiftUI の型は扱わず、`Bool` の表示状態と操作 API のみを公開する。
@Observable
@MainActor
final class PlaybackControlsVisibility {

    /// コントロールを表示中かどうか。
    private(set) var isVisible = false

    /// 表示状態になってから自動で非表示にするまでの時間（秒）。
    private let autoHideDelay: Duration

    /// 自動非表示のためのスリープ実装（テスト等で差し替え可能にするため注入する）。
    private let sleep: @Sendable (Duration) async throws -> Void

    /// 進行中の自動非表示タスク。新たに表示するたびに張り直す。
    private var autoHideTask: Task<Void, Never>?

    /// - Parameters:
    ///   - autoHideDelay: 表示してから自動で非表示にするまでの時間（既定 8 秒）。
    ///   - sleep: 自動非表示のための待機処理（既定は `Task.sleep`）。
    init(
        autoHideDelay: Duration = .seconds(8),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.autoHideDelay = autoHideDelay
        self.sleep = sleep
    }

    /// 表示・非表示をトグルする（画面タップ時に呼ぶ）。
    ///
    /// 表示へ切り替えた場合は自動非表示タイマーを開始し、非表示へ切り替えた場合はタイマーを止める。
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// コントロールを表示し、自動非表示タイマーを開始する。
    ///
    /// 再生準備完了（state が .ready）になったタイミングなど、明示的に表示したい場合に呼ぶ。
    func show() {
        isVisible = true
        scheduleAutoHide()
    }

    /// コントロールを非表示にし、自動非表示タイマーを止める。
    func hide() {
        autoHideTask?.cancel()
        autoHideTask = nil
        isVisible = false
    }

    // MARK: - Private

    /// 自動非表示タイマーを張り直す。既存のタイマーはキャンセルする。
    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task { [weak self, sleep, autoHideDelay] in
            do {
                try await sleep(autoHideDelay)
            } catch {
                // キャンセル時は何もしない（後続の表示操作が優先される）。
                return
            }
            guard let self else { return }
            self.isVisible = false
            self.autoHideTask = nil
        }
    }
}
