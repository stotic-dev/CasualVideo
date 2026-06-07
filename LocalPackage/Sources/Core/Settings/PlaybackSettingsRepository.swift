//
//  PlaybackSettingsRepository.swift
//  Core
//
//  再生デフォルト設定（PlaybackSettings）の永続化を抽象化する Repository（F-7）。
//
//  抽象化は protocol ではなく struct + クロージャで表現する（docs/architecture.md）。
//  型定義は `Core` に置き、本番実装（`.live`）は `App` が `Infra`（UserDefaultsClient）を用いて構築する。
//  永続化は UserDefaults のため同期 API でよい。
//

import SwiftUI

/// 再生デフォルト設定の読み書きを抽象化する Repository。
public struct PlaybackSettingsRepository: Sendable {

    /// 永続化された設定を読み込む。未設定時はデフォルト（`PlaybackSettings()`）を返す。
    public var load: @Sendable () -> PlaybackSettings

    /// 設定を永続化する。
    public var save: @Sendable (PlaybackSettings) -> Void

    public init(
        load: @escaping @Sendable () -> PlaybackSettings = { PlaybackSettings() },
        save: @escaping @Sendable (PlaybackSettings) -> Void = { _ in }
    ) {
        self.load = load
        self.save = save
    }
}

extension EnvironmentValues {

    /// 再生デフォルト設定 Repository の DI エントリ。
    ///
    /// 本番インスタンスは `App` が `Infra` の `UserDefaultsClient` を用いて構築し、
    /// `.environment(\.playbackSettingsRepository, .live(client:))` で注入する。
    /// 未注入時はメモリ上のデフォルト（永続化しない）フォールバック。
    @Entry public var playbackSettingsRepository = PlaybackSettingsRepository.unimplemented
}

extension PlaybackSettingsRepository {

    /// 未注入時のフォールバック。常にデフォルト設定を返し、保存は no-op。
    public static let unimplemented = PlaybackSettingsRepository(
        load: { PlaybackSettings() },
        save: { _ in }
    )
}
