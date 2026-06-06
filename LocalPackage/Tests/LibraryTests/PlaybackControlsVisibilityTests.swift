//
//  PlaybackControlsVisibilityTests.swift
//  LibraryTests
//
//  PlaybackControlsVisibility（再生コントロールの表示・非表示ドメインモデル）の振る舞いを検証する。
//
//  自動非表示タイマーは init に注入できる sleep クロージャで待機する。テストではこの sleep を
//  差し替え、待機の完了タイミングを明示的に制御することで自動非表示を決定的に検証する。
//

import Testing

@testable import Library

@MainActor
struct PlaybackControlsVisibilityTests {

    // MARK: - 初期状態 / 基本操作

    @Test("初期状態では isVisible は false")
    func initialStateIsHidden() {
        let visibility = PlaybackControlsVisibility(sleep: { _ in })

        #expect(visibility.isVisible == false)
    }

    @Test("show() で isVisible が true になる")
    func show_makesVisible() {
        // sleep が即座に完了すると自動非表示まで走ってしまうため、決して完了しない sleep を注入する。
        let visibility = PlaybackControlsVisibility(sleep: { _ in try await neverCompletingSleep() })

        visibility.show()

        #expect(visibility.isVisible == true)
    }

    @Test("toggle() で表示・非表示が切り替わる")
    func toggle_switchesVisibility() {
        let visibility = PlaybackControlsVisibility(sleep: { _ in try await neverCompletingSleep() })

        visibility.toggle()
        #expect(visibility.isVisible == true)

        visibility.toggle()
        #expect(visibility.isVisible == false)

        visibility.toggle()
        #expect(visibility.isVisible == true)
    }

    @Test("hide() で非表示になる")
    func hide_makesHidden() {
        let visibility = PlaybackControlsVisibility(sleep: { _ in try await neverCompletingSleep() })
        visibility.show()
        #expect(visibility.isVisible == true)

        visibility.hide()

        #expect(visibility.isVisible == false)
    }

    // MARK: - 自動非表示

    @Test("表示後 autoHideDelay 経過で自動的に isVisible が false になる")
    func autoHide_afterDelay() async {
        // sleep の完了を任意のタイミングで解放できるゲートを用意し、解放後に自動非表示が走ることを検証する。
        let gate = SleepGate()
        let visibility = PlaybackControlsVisibility(sleep: { _ in try await gate.wait() })

        visibility.show()
        #expect(visibility.isVisible == true)

        // 待機を解放し、自動非表示タスクが isVisible を false にするのを待つ。
        gate.release()
        await visibility.waitUntilHidden()

        #expect(visibility.isVisible == false)
    }

    @Test("連続で show() を呼ぶと前の自動非表示タイマーは張り直され、古いタイマーでは消えない")
    func consecutiveShow_reschedulesTimer() async {
        // 1 回目の show の sleep を解放しても、2 回目の show で張り直された後なら非表示にならないことを検証する。
        let firstGate = SleepGate()
        let secondGate = SleepGate()
        let callCount = Counter()
        let visibility = PlaybackControlsVisibility(sleep: { _ in
            let count = callCount.increment()
            if count == 1 {
                try await firstGate.wait()
            } else {
                try await secondGate.wait()
            }
        })

        visibility.show()
        visibility.show()  // タイマー張り直し（1 回目の sleep はキャンセルされる）

        // 1 回目の sleep を解放しても、その完了は古いタスクのものなので isVisible に影響しない。
        firstGate.release()
        await Task.yield()
        #expect(visibility.isVisible == true)

        // 2 回目（最新）のタイマーを解放すると非表示になる。
        secondGate.release()
        await visibility.waitUntilHidden()
        #expect(visibility.isVisible == false)
    }

    @Test("toggle() の連続呼び出しでも自動非表示タイマーが張り直される")
    func consecutiveToggle_reschedulesTimer() async {
        let firstGate = SleepGate()
        let secondGate = SleepGate()
        let callCount = Counter()
        let visibility = PlaybackControlsVisibility(sleep: { _ in
            let count = callCount.increment()
            if count == 1 {
                try await firstGate.wait()
            } else {
                try await secondGate.wait()
            }
        })

        visibility.toggle()  // 非表示 -> 表示（1 回目の sleep 開始）
        visibility.hide()    // 一旦非表示にして
        visibility.toggle()  // 非表示 -> 表示（2 回目の sleep 開始 / 張り直し相当）

        // 古い（1 回目の）タイマーを解放しても最新の表示は維持される。
        firstGate.release()
        await Task.yield()
        #expect(visibility.isVisible == true)

        secondGate.release()
        await visibility.waitUntilHidden()
        #expect(visibility.isVisible == false)
    }

    @Test("hide() で自動非表示タイマーがキャンセルされ、その後 sleep が完了しても状態は変わらない")
    func hide_cancelsAutoHideTimer() async {
        let gate = SleepGate()
        let visibility = PlaybackControlsVisibility(sleep: { _ in try await gate.wait() })

        visibility.show()
        #expect(visibility.isVisible == true)

        // hide はタイマーをキャンセルするので、その後に表示し直しても古いタイマーで消えない。
        visibility.hide()
        #expect(visibility.isVisible == false)

        // 元のタイマーの sleep を解放（キャンセル済みなので副作用なし）。
        gate.release()
        await Task.yield()
        #expect(visibility.isVisible == false)
    }
}

// MARK: - Test utilities

/// sleep の完了タイミングを外部から制御するゲート。
/// `wait()` は `release()` が呼ばれるまでサスペンドし、解放後は即座に完了する。
/// タスクがキャンセルされた場合は `CancellationError` を throw する（本番の Task.sleep と同じ挙動）。
private final class SleepGate: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private var released = false
    private var cancelled = false

    func wait() async throws {
        // 本番の Task.sleep と同様、解放済み判定よりもキャンセルを優先する。
        // （show() の張り直しでキャンセルされたタスクが、後から release() された
        //   ゲートを見て正常完了してしまう競合を防ぐ。）
        try Task.checkCancellation()
        if released { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if cancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    self.continuation = continuation
                }
            }
        } onCancel: {
            cancel()
        }
    }

    func release() {
        released = true
        continuation?.resume(returning: ())
        continuation = nil
    }

    private func cancel() {
        cancelled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

/// sleep 呼び出し回数をカウントするユーティリティ（@MainActor 上で使用）。
private final class Counter: @unchecked Sendable {
    private var count = 0
    func increment() -> Int {
        count += 1
        return count
    }
}

private extension PlaybackControlsVisibility {

    /// isVisible が false になるまでイベントループを譲りつつ待機する。
    /// 自動非表示タスクが MainActor 上で isVisible を更新するのを待つためのテストヘルパー。
    func waitUntilHidden() async {
        for _ in 0..<1000 {
            if isVisible == false { return }
            await Task.yield()
        }
    }
}

/// 自動非表示を発火させたくないテストで sleep として使う、十分に長くキャンセル可能な待機。
/// テスト中に解放されることはなく、テスト終了時はタスクのキャンセルで巻き取られる。
private func neverCompletingSleep() async throws {
    try await Task.sleep(for: .seconds(3600))
}
