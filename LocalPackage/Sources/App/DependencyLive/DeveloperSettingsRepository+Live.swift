//
//  DeveloperSettingsRepository+Live.swift
//  App
//
//  UserDefaultsClient（Infra）を用いて DeveloperSettingsRepository の本番インスタンスを組み立てる。
//
//  「どのキーへ保存するか」「未設定時のデフォルト」「String 値 ↔ CastBackend の対応づけ」という
//  使う側の都合はこの assemble 層で組み立てる。Infra（UserDefaultsClient）はプリミティブな
//  get/set のみに責務を限定する。
//

import Core
import Infra

extension DeveloperSettingsRepository {

    /// 永続化キー。
    private enum Key {
        static let castBackendOverride = "developer.castBackendOverride"
    }

    /// UserDefaults による永続化（`UserDefaultsClient`）を用いた本番インスタンス。
    static func live(client: UserDefaultsClient) -> DeveloperSettingsRepository {
        DeveloperSettingsRepository(
            load: {
                let defaultValue = DeveloperSettings()
                let backend = client.string(forKey: Key.castBackendOverride)
                    .flatMap(CastBackend.init(rawValue:)) ?? defaultValue.castBackendOverride
                return DeveloperSettings(castBackendOverride: backend)
            },
            save: { settings in
                client.setString(settings.castBackendOverride.rawValue, forKey: Key.castBackendOverride)
            }
        )
    }
}
