//
//  DeveloperSettingsRepository.swift
//  Core
//
//  開発者向け設定（DeveloperSettings）の永続化を抽象化する Repository。
//
//  抽象化は protocol ではなく struct + クロージャで表現する（docs/architecture.md）。
//  型定義は `Core` に置き、本番実装（`.live`）は `App` が `Infra`（UserDefaultsClient）を用いて構築する。
//
//  この Repository は `App` が `DeveloperSettingsStore` を組み立てる際にのみ用いる。
//  画面側は Repository を直接参照せず、注入された Store 経由で取得・更新する。
//

/// 開発者向け設定の読み書きを抽象化する Repository。
public struct DeveloperSettingsRepository: Sendable {

    /// 永続化された設定を読み込む。未設定時はデフォルト（`DeveloperSettings()`）を返す。
    public var load: @Sendable () -> DeveloperSettings

    /// 設定を永続化する。
    public var save: @Sendable (DeveloperSettings) -> Void

    public init(
        load: @escaping @Sendable () -> DeveloperSettings = { DeveloperSettings() },
        save: @escaping @Sendable (DeveloperSettings) -> Void = { _ in }
    ) {
        self.load = load
        self.save = save
    }
}
