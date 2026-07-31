//
//  RemotePlaybackSnapshot.swift
//  Infra
//
//  Cast デバイス側の再生状態スナップショット（Infra 内の Core 非依存な値型）。
//
//  Infra は Core に依存しないため、Core の `CastPlaybackState` / `PlaybackProgress` ではなく
//  素のプリミティブで Cast デバイスの状態を表す。Core 型への対応づけは `App` の assemble 層が担う。
//

import Foundation

/// Cast デバイス側の再生状態スナップショット。
public struct RemotePlaybackSnapshot: Sendable, Equatable {

    /// 現在の再生位置（秒）。
    public let position: TimeInterval
    /// 総再生時間（秒）。未確定なら 0。
    public let duration: TimeInterval
    /// 再生中か（再生 = true / 一時停止・停止 = false）。
    public let isPlaying: Bool

    public init(position: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        self.position = position
        self.duration = duration
        self.isPlaying = isPlaying
    }
}
