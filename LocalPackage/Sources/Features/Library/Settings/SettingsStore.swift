//
//  SettingsStore.swift
//  Library
//
//  再生デフォルト設定（ミュート・再生速度）の編集・永続化を担う Store（F-7）。
//

import Core
import Observation

/// 再生デフォルト設定を管理する Store。
///
/// `PlaybackSettingsRepository` を介して設定を読み込み、変更ごとに永続化する。
/// 特定画面に依存しないドメイン状態のみを持ち、UI 型は扱わない（docs/architecture.md）。
@Observable
@MainActor
final class SettingsStore {

    /// 現在の再生デフォルト設定。
    private(set) var settings: PlaybackSettings

    private let repository: PlaybackSettingsRepository

    init(repository: PlaybackSettingsRepository) {
        self.repository = repository
        self.settings = repository.load()
    }

    /// 永続化された設定を読み込み直す。
    func load() {
        settings = repository.load()
    }

    /// デフォルトミュートを設定し、永続化する。
    func setMuted(_ isMuted: Bool) {
        settings.isMuted = isMuted
        repository.save(settings)
    }

    /// デフォルト再生速度を設定し、永続化する。
    func setPlaybackRate(_ rate: PlaybackRate) {
        settings.playbackRate = rate
        repository.save(settings)
    }
}
