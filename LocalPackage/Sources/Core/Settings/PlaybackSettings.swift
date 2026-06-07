//
//  PlaybackSettings.swift
//  Core
//
//  再生のデフォルト設定（ミュート・再生速度）を表すドメイン型（F-7）。
//
//  再生画面（再生開始時の初期値適用）と設定画面（編集・永続化）の複数 Feature、および
//  Repository（永続化）から参照されるため Core に置く。
//

import Foundation

/// 再生のデフォルト設定。設定画面で編集し、再生開始時の初期値として適用する。
///
/// 永続化（UserDefaults）は `PlaybackSettingsRepository` 経由で `Infra` に隔離する。
public struct PlaybackSettings: Sendable, Hashable {

    /// デフォルトでミュート再生するか。未設定（初回）時のデフォルトは true（ミュート開始）。
    public var isMuted: Bool

    /// デフォルトの再生速度。
    public var playbackRate: PlaybackRate

    public init(isMuted: Bool = true, playbackRate: PlaybackRate = .normal) {
        self.isMuted = isMuted
        self.playbackRate = playbackRate
    }
}
