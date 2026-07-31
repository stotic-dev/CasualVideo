//
//  DeveloperSettings.swift
//  Core
//
//  開発者向けの設定を表すドメイン型。
//
//  本番ユーザー向けではなく、開発・検証用の切り替え（Cast バックエンドの手動選択など）を保持する。
//  永続化（UserDefaults）は `DeveloperSettingsRepository` 経由で `Infra` に隔離する。
//

/// 開発者向け設定。
public struct DeveloperSettings: Sendable, Hashable {

    /// Cast 送出バックエンドの手動 override。既定は `.auto`（環境に応じた自動選択）。
    public var castBackendOverride: CastBackend

    public init(castBackendOverride: CastBackend = .auto) {
        self.castBackendOverride = castBackendOverride
    }
}
