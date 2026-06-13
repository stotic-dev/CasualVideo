//
//  SettingsStoreTests.swift
//  LibraryTests
//
//  SettingsStore（再生デフォルト設定の編集・永続化 F-7）のロジックを検証する。
//
//  SettingsStore は設定の永続化を PlaybackSettingsRepository（クロージャ保持の struct）へ委譲する。
//  テストでは本番の `.live` ではなくクロージャを差し替えた Repository を注入し（docs/testing.md）、
//  「init / load での読み込み反映」「編集での状態更新と永続化（save）への委譲」を検証する。
//
//  各ケースは AAA パターン（Arrange / Act / Assert）をコメントで明示する。状態検証は公開状態を
//  まとめて検証する共通 Assertion（`assertState`）で行い、副作用（save）の検証はケースごとに別途行う。
//

import Core
import Testing

@testable import Library

@MainActor
struct SettingsStoreTests {

    // MARK: - Fixtures

    /// load が返す値と save された値を Box で記録できる Repository を作る。
    private func recordingRepository(
        loadValue: Box<PlaybackSettings>,
        savedValues: Box<[PlaybackSettings]> = Box([])
    ) -> PlaybackSettingsRepository {
        PlaybackSettingsRepository(
            load: { loadValue.value },
            save: { savedValues.value.append($0) }
        )
    }

    // MARK: - init / load

    @Test("init は repository.load() の値を settings に反映する")
    func init_reflectsLoadedSettings() {
        // Arrange
        let loaded = PlaybackSettings(isMuted: false, playbackRate: .fast15)
        let repository = recordingRepository(loadValue: Box(loaded))

        // Act
        let store = SettingsStore(repository: repository)

        // Assert
        assertState(store, ExpectedState(isMuted: false, playbackRate: .fast15))
    }

    @Test("load は repository.load() の最新値へ更新する")
    func load_updatesToLatestValue() {
        // Arrange
        let loadValue = Box(PlaybackSettings(isMuted: true, playbackRate: .normal))
        let store = SettingsStore(repository: recordingRepository(loadValue: loadValue))
        assertState(store, ExpectedState(isMuted: true, playbackRate: .normal))

        // Act: 永続化側が更新された後に load し直す
        loadValue.value = PlaybackSettings(isMuted: false, playbackRate: .double)
        store.load()

        // Assert
        assertState(store, ExpectedState(isMuted: false, playbackRate: .double))
    }

    // MARK: - setMuted

    @Test("setMuted は settings.isMuted を更新し、更新後の settings を save へ渡す")
    func setMuted_updatesAndPersists() {
        // Arrange
        let savedValues = Box<[PlaybackSettings]>([])
        let store = SettingsStore(
            repository: recordingRepository(
                loadValue: Box(PlaybackSettings(isMuted: true, playbackRate: .fast15)),
                savedValues: savedValues
            )
        )

        // Act
        store.setMuted(false)

        // Assert: 状態が更新され、他の項目（速度）は維持されたまま永続化される
        assertState(store, ExpectedState(isMuted: false, playbackRate: .fast15))
        #expect(savedValues.value == [PlaybackSettings(isMuted: false, playbackRate: .fast15)])
    }

    // MARK: - setPlaybackRate

    @Test("setPlaybackRate は settings.playbackRate を更新し、更新後の settings を save へ渡す")
    func setPlaybackRate_updatesAndPersists() {
        // Arrange
        let savedValues = Box<[PlaybackSettings]>([])
        let store = SettingsStore(
            repository: recordingRepository(
                loadValue: Box(PlaybackSettings(isMuted: true, playbackRate: .normal)),
                savedValues: savedValues
            )
        )

        // Act
        store.setPlaybackRate(.double)

        // Assert: 状態が更新され、他の項目（ミュート）は維持されたまま永続化される
        assertState(store, ExpectedState(isMuted: true, playbackRate: .double))
        #expect(savedValues.value == [PlaybackSettings(isMuted: true, playbackRate: .double)])
    }

    // MARK: - 共通 Assertion

    /// SettingsStore の公開状態（settings）すべての期待値。
    private struct ExpectedState {
        var isMuted: Bool = true
        var playbackRate: PlaybackRate = .normal
    }

    /// 公開状態を一括検証する共通 Assertion。
    ///
    /// 副作用として変化する項目だけでなく公開状態すべてを毎回検証することで、
    /// 実装変更による意図しない状態変化を検知する。Repository（Mock）の検証は各ケースで別途行う。
    private func assertState(
        _ store: SettingsStore,
        _ expected: ExpectedState,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(store.settings.isMuted == expected.isMuted, sourceLocation: sourceLocation)
        #expect(store.settings.playbackRate == expected.playbackRate, sourceLocation: sourceLocation)
    }
}

/// クロージャ内から書き換え可能な参照ボックス。@MainActor 上のテストでのみ使用する。
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
