//
//  PlaybackStoreTests.swift
//  LibraryTests
//
//  PlaybackStore（アプリスコープの再生 Store / F-3 PIP 復帰）のロジックを検証する。
//
//  PlaybackStore は再生エンジン操作・PIP 操作を VideoPlayerProxy（クロージャ保持の struct）へ委譲する。
//  テストでは本番の `.live` ではなくクロージャを差し替えた Proxy を注入し（docs-internal/testing.md）、
//  「再生開始での提示」「PIP 移行での提示解除」「PIP 復帰での再提示」という提示状態のロジックを検証する。
//  各ケースは AAA パターン（Arrange / Act / Assert）をコメントで明示する。
//

import Core
import Foundation
import Testing

@testable import Library

@MainActor
struct PlaybackStoreTests {

    // MARK: - Fixtures

    private func makeAsset(id: String) -> VideoAsset {
        VideoAsset(id: id, duration: 1, creationDate: nil, isInCloud: false)
    }

    private func makeStore(playerProxy: VideoPlayerProxy) -> PlaybackStore {
        PlaybackStore(
            playerProxy: playerProxy,
            nowPlayingInfoProxy: NowPlayingInfoProxy(),
            settingsStore: SettingsStore(repository: .init())
        )
    }

    /// 指定条件が満たされるまで（または上限まで）メインアクター上で待機する。
    private func waitUntil(_ condition: @MainActor () -> Bool, max: Int = 1000) async {
        var iterations = 0
        while !condition() && iterations < max {
            await Task.yield()
            iterations += 1
        }
    }

    // MARK: - start()

    @Test("start は全画面プレイヤーを提示し、読み込み完了で ready になる")
    func start_presentsPlayerAndBecomesReady() async {
        // Arrange
        let playbackStore = makeStore(playerProxy: VideoPlayerProxy(loadAndPlay: { _ in true }))

        // Act
        playbackStore.start(playlist: [makeAsset(id: "a"), makeAsset(id: "b")], startIndex: 1)

        // Assert: 取得を待たずに即座に提示し、ローディング状態になる。
        #expect(playbackStore.isPlayerPresented)
        #expect(playbackStore.phase == .loading)

        // Assert: 読み込み完了で ready になり、連続再生 Store が生成される。
        await waitUntil { playbackStore.phase != .loading }
        #expect(playbackStore.phase == .ready)
        #expect(playbackStore.playlistStore?.currentAsset?.id == "b")
    }

    @Test("空のプレイリストで start すると failed になる")
    func start_withEmptyPlaylist_becomesFailed() async {
        // Arrange
        let playbackStore = makeStore(playerProxy: VideoPlayerProxy(loadAndPlay: { _ in true }))

        // Act
        playbackStore.start(playlist: [])

        // Assert
        await waitUntil { playbackStore.phase != .loading }
        #expect(playbackStore.phase == .failed)
        #expect(playbackStore.playlistStore == nil)
    }

    // MARK: - enterPictureInPicture()

    @Test("enterPictureInPicture は startPictureInPicture を呼び、開始完了で提示を解除する")
    func enterPictureInPicture_dismissesOnDidStart() {
        // Arrange: 開始完了コールバックを捕捉する Proxy を注入する。
        let captured = Box<(@MainActor @Sendable () -> Void)?>(nil)
        let playbackStore = makeStore(
            playerProxy: VideoPlayerProxy(startPictureInPicture: { onDidStart in captured.value = onDidStart })
        )
        playbackStore.start(playlist: [makeAsset(id: "a")])
        #expect(playbackStore.isPlayerPresented)

        // Act: PIP へ移行する。
        playbackStore.enterPictureInPicture()

        // Assert: 開始要求のみでは提示は解除されない（中断防止のため開始完了を待つ）。
        #expect(playbackStore.isPlayerPresented)

        // Act: 開始完了を通知する。
        captured.value?()

        // Assert: 全画面プレイヤーが閉じる（セッションは保持される）。
        #expect(!playbackStore.isPlayerPresented)
    }

    // MARK: - PIP 復帰

    @Test("PIP の戻る要求で全画面プレイヤーを再提示する")
    func restore_representsPlayer() {
        // Arrange: restore ハンドラを捕捉する Proxy を注入する（init で購読登録される）。
        let captured = Box<(@MainActor @Sendable () -> Void)?>(nil)
        let playbackStore = makeStore(
            playerProxy: VideoPlayerProxy(observePictureInPictureRestore: { handler in captured.value = handler })
        )
        // PIP 中（提示解除済み）を再現する。
        playbackStore.isPlayerPresented = false

        // Act: PIP の「戻る」要求を発火する。
        captured.value?()

        // Assert: 全画面プレイヤーが再提示される。
        #expect(playbackStore.isPlayerPresented)
    }
}

/// クロージャ越しに捕捉した値を共有するための簡易ボックス。
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
