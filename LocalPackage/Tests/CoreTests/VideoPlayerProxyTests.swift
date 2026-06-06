//
//  VideoPlayerProxyTests.swift
//  CoreTests
//
//  VideoPlayerProxy（クロージャ保持の struct）の委譲挙動を検証する（F-3）。
//
//  Proxy は AVPlayer 操作を抽象化する struct で、各操作はクロージャへ委譲される。
//  ここでは「Proxy のメソッド呼び出しが、注入したクロージャへ正しく委譲されること」を検証する。
//  本番の `.live`（Infra の Client / AudioSession への委譲）は App 層の assemble であり、
//  テスト対象外（docs/testing.md）。よって Core で型の委譲契約のみを検証する。
//

import Testing

@testable import Core

@MainActor
struct VideoPlayerProxyTests {
    
    // MARK: - prepareForBackgroundPlayback

    @Test("prepareForBackgroundPlayback は注入したクロージャへ委譲される")
    func prepareForBackgroundPlayback_invokesInjectedClosure() {
        let called = Box(false)
        let proxy = VideoPlayerProxy(
            prepareForBackgroundPlayback: { called.value = true }
        )

        proxy.prepareForBackgroundPlayback()

        #expect(called.value)
    }

    @Test("デフォルトの prepareForBackgroundPlayback は何もせずクラッシュしない")
    func prepareForBackgroundPlayback_defaultIsNoop() {
        let proxy = VideoPlayerProxy()
        // デフォルト実装（{}）が呼んでもクラッシュしないことを確認する。
        proxy.prepareForBackgroundPlayback()
    }

    // MARK: - 再生開始シーケンス（start() が踏む順序）

    @Test("再生準備では prepareForBackgroundPlayback が loadAndPlay より先に呼ばれる")
    func backgroundPlaybackPreparation_precedesLoadAndPlay() async {
        // VideoPlayerScreen.start() が踏むシーケンスと同じ順序を Proxy 経由で再現し、
        // オーディオセッション構成が再生開始（loadAndPlay）より前に行われることを検証する。
        let order = Box<[String]>([])
        let proxy = VideoPlayerProxy(
            loadAndPlay: { _ in
                await MainActor.run { order.value.append("loadAndPlay") }
                return true
            },
            prepareForBackgroundPlayback: { order.value.append("prepare") }
        )

        proxy.prepareForBackgroundPlayback()
        _ = await proxy.loadAndPlay("asset-id")

        #expect(order.value == ["prepare", "loadAndPlay"])
    }

    // MARK: - その他の操作委譲（回帰防止）

    @Test("play / pause / setMuted も注入したクロージャへ委譲される")
    func playerOperations_invokeInjectedClosures() {
        let played = Box(false)
        let paused = Box(false)
        let muted = Box<Bool?>(nil)
        let proxy = VideoPlayerProxy(
            play: { played.value = true },
            pause: { paused.value = true },
            setMuted: { muted.value = $0 }
        )

        proxy.play()
        proxy.pause()
        proxy.setMuted(true)

        #expect(played.value)
        #expect(paused.value)
        #expect(muted.value == true)
    }

    // MARK: - observeDidPlayToEnd（F-4 連続再生の自動遷移フック）

    @Test("observeDidPlayToEnd は注入したクロージャへ委譲し、登録ハンドラを引き渡す")
    func observeDidPlayToEnd_invokesInjectedClosureWithHandler() {
        let registered = Box<(@MainActor @Sendable () -> Void)?>(nil)
        let proxy = VideoPlayerProxy(
            observeDidPlayToEnd: { registered.value = $0 }
        )

        let fired = Box(false)
        proxy.observeDidPlayToEnd { fired.value = true }

        // 登録ハンドラが委譲先へ正しく渡り、呼び出すと発火することを確認する。
        #expect(registered.value != nil)
        registered.value?()
        #expect(fired.value)
    }

    @Test("デフォルトの observeDidPlayToEnd は何もせずクラッシュしない")
    func observeDidPlayToEnd_defaultIsNoop() {
        let proxy = VideoPlayerProxy()
        // デフォルト実装（{ _ in }）にハンドラを渡してもクラッシュしないことを確認する。
        proxy.observeDidPlayToEnd {}
    }
}

// MARK: - Test utility

/// クロージャ内から書き換え可能な参照ボックス。@MainActor 上のテストでのみ使用する。
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
