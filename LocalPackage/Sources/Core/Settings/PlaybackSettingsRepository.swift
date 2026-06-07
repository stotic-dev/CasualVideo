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
//  この Repository は `App` が `SettingsStore`（共有 Store）を組み立てる際にのみ用いる。
//  画面側は Repository を直接参照せず、注入された `SettingsStore` 経由で設定を取得・更新する。
//

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
