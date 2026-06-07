//
//  SettingsStore.swift
//  Library
//
//  再生デフォルト設定（ミュート・再生速度）の編集・永続化を担う Store（F-7）。
//

import Core
import Observation

/// 再生デフォルト設定を管理する共有 Store。
///
/// `PlaybackSettingsRepository` を介して設定を読み込み、変更ごとに永続化する。
/// 特定画面に依存しないドメイン状態のみを持ち、UI 型は扱わない（docs/architecture.md）。
/// `App` で assemble して型ベースで Environment へ注入し、設定画面・再生画面など複数画面から
/// `@Environment(SettingsStore.self)` で共有参照する。
@Observable
@MainActor
public final class SettingsStore {

    /// 現在の再生デフォルト設定。
    public private(set) var settings: PlaybackSettings

    private let repository: PlaybackSettingsRepository

    public init(repository: PlaybackSettingsRepository = .init()) {
        self.repository = repository
        self.settings = repository.load()
    }

    /// 永続化された設定を読み込み直す。
    public func load() {
        settings = repository.load()
    }

    /// デフォルトミュートを設定し、永続化する。
    public func setMuted(_ isMuted: Bool) {
        settings.isMuted = isMuted
        repository.save(settings)
    }

    /// デフォルト再生速度を設定し、永続化する。
    public func setPlaybackRate(_ rate: PlaybackRate) {
        settings.playbackRate = rate
        repository.save(settings)
    }
}
