//
//  PlaybackSettingsRepository+Live.swift
//  App
//
//  UserDefaultsClient（Infra）を用いて PlaybackSettingsRepository の本番インスタンスを組み立てる（F-7）。
//
//  「どのキーへ保存するか」「未設定時のデフォルト」「rate 値（Double）↔ PlaybackRate の対応づけ」という
//  使う側の都合（ドメイン型との対応づけ）はこの assemble 層で組み立てる。
//  Infra（UserDefaultsClient）はプリミティブな get/set のみに責務を限定する。
//

import Core
import Infra

extension PlaybackSettingsRepository {

    /// 永続化キー。
    private enum Key {
        static let isMuted = "playback.isMuted"
        static let playbackRate = "playback.playbackRate"
    }

    /// UserDefaults による永続化（`UserDefaultsClient`）を用いた本番インスタンス。
    static func live(client: UserDefaultsClient) -> PlaybackSettingsRepository {
        PlaybackSettingsRepository(
            load: {
                // 未設定のキーはデフォルト値（`PlaybackSettings()`）に倒す。
                let defaultValue = PlaybackSettings()
                let isMuted = client.bool(forKey: Key.isMuted) ?? defaultValue.isMuted
                let rate = client.double(forKey: Key.playbackRate)
                    .flatMap(PlaybackRate.init(rawValue:)) ?? defaultValue.playbackRate
                return PlaybackSettings(isMuted: isMuted, playbackRate: rate)
            },
            save: { settings in
                client.setBool(settings.isMuted, forKey: Key.isMuted)
                client.setDouble(settings.playbackRate.rawValue, forKey: Key.playbackRate)
            }
        )
    }
}
