//
//  PlaybackControlsVisibilityTests.swift
//  LibraryTests
//
//  PlaybackControlsVisibility（再生コントロールの表示・非表示ドメインモデル）の振る舞いを検証する。
//
//  自動非表示タイマーは init に注入できる sleep クロージャで待機する。テストではこの sleep を
//  差し替え、待機の完了タイミングを明示的に制御することで自動非表示を決定的に検証する。
//
//  プレゼンテーションロジックのテストは複雑になりがちなため、各ケースは AAA パターン
//  （Arrange / Act / Assert）をコメントで明示する。状態検証は公開状態をまとめて検証する
//  共通 Assertion（`assertState`）で行い、副作用に関連する Mock の検証はケースごとに別途行う。
//

import Testing

@testable import Library

@MainActor
struct PlaybackControlsVisibilityTests {

    // MARK: - 初期状態 / 基本操作

    @Test("初期状態では isVisible は false")
    func initialStateIsHidden() {
        // Arrange
        let visibility = PlaybackControlsVisibility(sleep: { _ in })

        // Act
        // （操作なし。生成直後の初期状態を検証する。）

        // Assert
        assertState(visibility, ExpectedState(isVisible: false))
    }

    @Test("show() で isVisible が true になる")
    func show_makesVisible() {
        // Arrange: sleep が即座に完了すると自動非表示まで走ってしまうため、決して完了しない sleep を注入する。
        let visibility = PlaybackControlsVisibility(sleep: { _ in try await neverCompletingSleep() })

        // Act
        visibility.show()

        // Assert
        assertState(visibility, ExpectedState(isVisible: true))
    }

    @Test("toggle() で表示・非表示が切り替わる")
    func toggle_switchesVisibility() {
        // Arrange
        let visibility = PlaybackControlsVisibility(sleep: { _ in try await neverCompletingSleep() })

        // Act & Assert: 呼ぶたびに表示状態が反転する
        visibility.toggle()
        assertState(visibility, ExpectedState(isVisible: true))

        visibility.toggle()
        assertState(visibility, ExpectedState(isVisible: false))

        visibility.toggle()
        assertState(visibility, ExpectedState(isVisible: true))
    }

    @Test("hide() で非表示になる")
    func hide_makesHidden() {
        // Arrange
        let visibility = PlaybackControlsVisibility(sleep: { _ in try await neverCompletingSleep() })
        visibility.show()
        assertState(visibility, ExpectedState(isVisible: true))

        // Act
        visibility.hide()

        // Assert
        assertState(visibility, ExpectedState(isVisible: false))
    }

    // MARK: - 自動非表示

    @Test("表示後 autoHideDelay 経過で自動的に isVisible が false になる")
    func autoHide_afterDelay() async {
        // Arrange: sleep の完了を任意のタイミングで解放できるゲートを用意する。
        let gate = SleepGate()
        let visibility = PlaybackControlsVisibility(sleep: { _ in try await gate.wait() })
        visibility.show()
        assertState(visibility, ExpectedState(isVisible: true))

        // Act: 待機を解放し、自動非表示タスクが isVisible を false にするのを待つ。
        gate.release()
        await visibility.waitUntilHidden()

        // Assert
        assertState(visibility, ExpectedState(isVisible: false))
    }

    @Test("連続で show() を呼ぶと前の自動非表示タイマーは張り直され、古いタイマーでは消えない")
    func consecutiveShow_reschedulesTimer() async {
        // Arrange: 1 回目 / 2 回目の sleep をそれぞれ別ゲートで制御する。
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

        // Act: タイマー張り直し（1 回目の sleep はキャンセルされる）
        visibility.show()
        visibility.show()

        // Act & Assert: 1 回目の sleep を解放してもそれは古いタスクのものなので影響しない
        firstGate.release()
        assertState(visibility, ExpectedState(isVisible: true))

        // Act & Assert: 2 回目（最新）のタイマーを解放すると非表示になる
        secondGate.release()
        await visibility.waitUntilHidden()
        assertState(visibility, ExpectedState(isVisible: false))
    }

    @Test("toggle() の連続呼び出しでも自動非表示タイマーが張り直される")
    func consecutiveToggle_reschedulesTimer() async {
        // Arrange
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

        // Act: 表示 → 非表示 → 表示（2 回目の sleep 開始 / 張り直し相当）
        visibility.toggle()  // 非表示 -> 表示（1 回目の sleep 開始）
        visibility.hide()    // 一旦非表示にして
        visibility.toggle()  // 非表示 -> 表示（2 回目の sleep 開始）

        // Act & Assert: 古い（1 回目の）タイマーを解放しても最新の表示は維持される
        firstGate.release()
        await Task.yield()
        assertState(visibility, ExpectedState(isVisible: true))

        // Act & Assert: 最新のタイマーを解放すると非表示になる
        secondGate.release()
        await visibility.waitUntilHidden()
        assertState(visibility, ExpectedState(isVisible: false))
    }

    @Test("hide() で自動非表示タイマーがキャンセルされ、その後 sleep が完了しても状態は変わらない")
    func hide_cancelsAutoHideTimer() async {
        // Arrange
        let gate = SleepGate()
        let visibility = PlaybackControlsVisibility(sleep: { _ in try await gate.wait() })
        visibility.show()
        assertState(visibility, ExpectedState(isVisible: true))

        // Act: hide はタイマーをキャンセルする
        visibility.hide()
        assertState(visibility, ExpectedState(isVisible: false))

        // Act & Assert: 元のタイマーの sleep を解放してもキャンセル済みなので副作用なし
        gate.release()
        await Task.yield()
        assertState(visibility, ExpectedState(isVisible: false))
    }

    // MARK: - 共通 Assertion

    /// PlaybackControlsVisibility の公開状態すべての期待値。
    ///
    /// 公開状態は `isVisible` のみ。各テストはこの値を指定して渡す。
    private struct ExpectedState {
        var isVisible: Bool = false
    }

    /// 公開状態を一括検証する共通 Assertion。
    ///
    /// 公開状態すべてを毎回検証することで、実装変更による意図しない状態変化を検知する。
    /// Mock（注入した sleep の挙動）の検証は各ケースで別途行う。
    private func assertState(
        _ visibility: PlaybackControlsVisibility,
        _ expected: ExpectedState,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(visibility.isVisible == expected.isVisible, sourceLocation: sourceLocation)
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
