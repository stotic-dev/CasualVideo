//
//  DeveloperSettingsStore.swift
//  Library
//
//  開発者向け設定（Cast バックエンドの手動切り替え等）の編集・永続化を担う Store。
//

import Core
import Observation

/// 開発者向け設定を管理する共有 Store。
///
/// `DeveloperSettingsRepository` を介して設定を読み込み、変更ごとに永続化する。
/// `App` で assemble して型ベースで Environment へ注入し、設定画面（開発者セクション）から参照する。
/// 起動時の Cast バックエンド選択（`RootScreen`）もこの Store が読み込んだ値を用いる。
@Observable
@MainActor
public final class DeveloperSettingsStore {

    /// 現在の開発者向け設定。
    public private(set) var settings: DeveloperSettings

    private let repository: DeveloperSettingsRepository

    public init(repository: DeveloperSettingsRepository = .init()) {
        self.repository = repository
        self.settings = repository.load()
    }

    /// Cast バックエンドの手動 override を設定し、永続化する。
    ///
    /// 反映は次回起動時（`RootScreen` の assemble 時に解決）となる。
    public func setCastBackendOverride(_ backend: CastBackend) {
        settings.castBackendOverride = backend
        repository.save(settings)
    }
}
