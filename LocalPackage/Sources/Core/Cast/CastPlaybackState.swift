//
//  CastPlaybackState.swift
//  Core
//
//  Cast デバイス側の再生状態を表すドメインモデル。
//
//  Cast 再生中、再生画面のシークバー・再生/一時停止ボタンを Cast デバイスの実状態へ同期するために、
//  Cast 側の「再生位置・長さ・再生中か」を 1 つに畳む。位置・長さは `PlaybackProgress` を再利用する。
//  Cast SDK（GoogleCast）/ `AVSystemRouting` の具体型には依存せず `Core` で完結する値型として定義する。
//

/// Cast デバイス側の再生状態。
public struct CastPlaybackState: Sendable, Equatable {

    /// Cast デバイスの再生進捗（現在位置・長さ）。
    public var progress: PlaybackProgress

    /// Cast デバイスで再生中か（再生 = true / 一時停止・停止 = false）。
    public var isPlaying: Bool

    public init(progress: PlaybackProgress = PlaybackProgress(), isPlaying: Bool = false) {
        self.progress = progress
        self.isPlaying = isPlaying
    }
}
