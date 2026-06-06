//
//  PlaybackProgress.swift
//  Core
//
//  シークバー表示・シーク操作のための再生進捗を表すドメイン型。
//

import Foundation

/// 現在再生中アイテムの再生進捗（現在位置・総再生時間）。
///
/// シークバーの表示（現在位置 / 全体長）とシーク操作の基礎値として用いる。
/// 再生エンジン（AVPlayer）の型（`CMTime` 等）は扱わず、秒単位の値型のみで表現する。
/// 再生エンジンの時間監視・シークは `VideoPlayerProxy` 経由で `Infra` に隔離する。
public struct PlaybackProgress: Sendable, Hashable {

    /// 現在の再生位置（秒）。
    public var currentTime: TimeInterval

    /// 総再生時間（秒）。未確定（ライブ等）の場合は 0。
    public var duration: TimeInterval

    public init(currentTime: TimeInterval = 0, duration: TimeInterval = 0) {
        self.currentTime = currentTime
        self.duration = duration
    }

    /// シークバーに表示できる有効な長さを持つか（総再生時間が正の有限値か）。
    public var isSeekable: Bool {
        duration.isFinite && duration > 0
    }

    /// 進捗割合（0...1）。総再生時間が無効なら 0。
    public var fraction: Double {
        guard isSeekable else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
}
