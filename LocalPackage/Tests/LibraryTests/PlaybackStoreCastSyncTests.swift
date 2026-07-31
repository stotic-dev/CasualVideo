//
//  PlaybackStoreCastSyncTests.swift
//  LibraryTests
//
//  Cast 再生中の再生位置・再生状態の同期ロジック（PlaybackStore）を検証する。
//
//  PlaybackStore は Cast 操作・状態購読を CastProxy（クロージャ保持の struct）へ委譲する。
//  テストではクロージャを差し替えた CastProxy を注入し（docs-internal/testing.md）、
//  「リモート状態の反映」「再生/一時停止・シーク操作の送出と楽観更新」「切断でのリセット」を検証する。
//

import Core
import Foundation
import Testing

@testable import Library

@MainActor
struct PlaybackStoreCastSyncTests {

    // MARK: - Fixtures

    private func makeStore(castProxy: CastProxy) -> PlaybackStore {
        PlaybackStore(
            playerProxy: VideoPlayerProxy(),
            nowPlayingInfoProxy: NowPlayingInfoProxy(),
            settingsStore: SettingsStore(repository: .init()),
            castProxy: castProxy
        )
    }

    // MARK: - リモート状態の反映

    @Test("observeRemoteState の通知が castState に反映される")
    func remoteState_updatesCastState() {
        // Arrange: リモート状態ハンドラを捕捉する CastProxy を注入する（init で購読登録される）。
        let captured = Box<(@MainActor @Sendable (CastPlaybackState) -> Void)?>(nil)
        let store = makeStore(castProxy: CastProxy(observeRemoteState: { handler in captured.value = handler }))

        // Act: Cast デバイス側の状態を通知する。
        let state = CastPlaybackState(progress: PlaybackProgress(currentTime: 12, duration: 100), isPlaying: true)
        captured.value?(state)

        // Assert: castState に反映される。
        #expect(store.castState == state)
    }

    // MARK: - 再生 / 一時停止の送出

    @Test("castTogglePlayPause は停止中なら play を送り、楽観的に再生中へ更新する")
    func castTogglePlayPause_whenPaused_sendsPlay() {
        // Arrange
        let playCount = Box(0)
        let pauseCount = Box(0)
        let store = makeStore(
            castProxy: CastProxy(play: { playCount.value += 1 }, pause: { pauseCount.value += 1 })
        )
        // 初期状態は一時停止中。

        // Act
        store.castTogglePlayPause()

        // Assert: play を 1 回送り、楽観更新で再生中になる。
        #expect(playCount.value == 1)
        #expect(pauseCount.value == 0)
        #expect(store.castState.isPlaying)
    }

    @Test("castTogglePlayPause は再生中なら pause を送り、楽観的に一時停止へ更新する")
    func castTogglePlayPause_whenPlaying_sendsPause() {
        // Arrange: 再生中状態を作るためのリモート状態ハンドラも捕捉する。
        let remote = Box<(@MainActor @Sendable (CastPlaybackState) -> Void)?>(nil)
        let playCount = Box(0)
        let pauseCount = Box(0)
        let store = makeStore(
            castProxy: CastProxy(
                observeRemoteState: { remote.value = $0 },
                play: { playCount.value += 1 },
                pause: { pauseCount.value += 1 }
            )
        )
        remote.value?(CastPlaybackState(progress: PlaybackProgress(currentTime: 0, duration: 100), isPlaying: true))

        // Act
        store.castTogglePlayPause()

        // Assert: pause を 1 回送り、楽観更新で一時停止になる。
        #expect(pauseCount.value == 1)
        #expect(playCount.value == 0)
        #expect(!store.castState.isPlaying)
    }

    // MARK: - シークの送出

    @Test("castSeek は seek を送り、castState の位置を即時反映する")
    func castSeek_sendsSeekAndUpdatesPosition() {
        // Arrange
        let seekTo = Box<TimeInterval?>(nil)
        let remote = Box<(@MainActor @Sendable (CastPlaybackState) -> Void)?>(nil)
        let store = makeStore(
            castProxy: CastProxy(observeRemoteState: { remote.value = $0 }, seek: { seekTo.value = $0 })
        )
        remote.value?(CastPlaybackState(progress: PlaybackProgress(currentTime: 0, duration: 100), isPlaying: true))

        // Act
        store.castSeek(to: 42)

        // Assert: seek を送り、表示用に位置を即時反映する。
        #expect(seekTo.value == 42)
        #expect(store.castState.progress.currentTime == 42)
    }

    // MARK: - 切断でのリセット

    @Test("Cast 切断で castState がリセットされる")
    func disconnect_resetsCastState() {
        // Arrange: セッション状態・リモート状態の両ハンドラを捕捉する。
        let session = Box<(@MainActor @Sendable (CastSessionState) -> Void)?>(nil)
        let remote = Box<(@MainActor @Sendable (CastPlaybackState) -> Void)?>(nil)
        let store = makeStore(
            castProxy: CastProxy(
                observeSessionState: { session.value = $0 },
                observeRemoteState: { remote.value = $0 }
            )
        )
        remote.value?(CastPlaybackState(progress: PlaybackProgress(currentTime: 30, duration: 100), isPlaying: true))
        #expect(store.castState.isPlaying)

        // Act: 切断を通知する。
        session.value?(.disconnected)

        // Assert: castState が初期状態へ戻る。
        #expect(store.castState == CastPlaybackState())
    }
}

/// クロージャ越しに捕捉した値を共有するための簡易ボックス。
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
