//
//  NowPlayingInfoClient.swift
//  Infra
//
//  MPNowPlayingInfoCenter / MPRemoteCommandCenter の唯一の窓口（single source of truth）。
//
//  Now Playing 表示（ロック画面・コントロールセンター）とリモートコマンド（再生/一時停止・次/前・シーク）の
//  システム連携（F-5）をここに閉じ込める。再生エンジンや「どの動画か」という使う側の都合は持たず、
//  値の反映とコマンドハンドラ登録だけに責務を限定する。他の Infra Client には依存しない。
//
//  MediaPlayer は iOS のみで利用可能なため、テストランナー（macOS）では全 API を no-op スタブとし、
//  ビルド整合を保つ（AudioSessionClient / PictureInPictureClient の `#if` 作法を踏襲）。
//

import CoreGraphics
import Foundation

#if canImport(MediaPlayer) && os(iOS)
import MediaPlayer
import UIKit
#endif

/// リモートコマンドの種別。
///
/// `Core` の `RemoteCommand` には依存せず（Infra は Core を参照しない方針）、Infra ローカルの
/// enum でコマンドを表現する。`Core` 型への変換は `App`（assemble 層）が担う
/// （`PhotoVideoAsset → VideoAsset` と同じ方針）。
public enum NowPlayingRemoteCommand: Sendable, Hashable {
    case play
    case pause
    case toggle
    case next
    case previous
    case seek(TimeInterval)
}

/// Now Playing 情報とリモートコマンドを集約するクライアント。
///
/// `update(...)` で Now Playing 情報を反映し、`observeCommand(_:)` でリモートコマンドを購読する。
/// iOS 以外（テストランナーの macOS）では全 API が no-op。
@MainActor
public final class NowPlayingInfoClient {

    public init() {}

    /// Now Playing 情報を反映する。
    ///
    /// - Parameters:
    ///   - title: 表示タイトル。
    ///   - duration: 総再生時間（秒）。
    ///   - elapsedTime: 現在の再生位置（秒）。
    ///   - rate: 再生レート（再生中 1.0 / 一時停止 0.0）。
    ///   - artwork: アートワーク画像（無い場合は nil。既存のアートワークは維持する）。
    public func update(
        title: String,
        duration: TimeInterval,
        elapsedTime: TimeInterval,
        rate: Double,
        artwork: CGImage?
    ) {
        #if canImport(MediaPlayer) && os(iOS)
        let center = MPNowPlayingInfoCenter.default()
        var info = center.nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        if let artwork {
            info[MPMediaItemPropertyArtwork] = Self.makeArtwork(from: artwork)
        }
        center.nowPlayingInfo = info
        #endif
    }

    #if canImport(MediaPlayer) && os(iOS)
    /// アートワークを生成する。
    ///
    /// `requestHandler` は OS がバックグラウンドスレッドから描画のために呼び出す。`@MainActor` の
    /// インスタンスメソッド内で生成するとクロージャが MainActor 隔離を継承し、別スレッド呼び出しで
    /// actor-executor 不一致のクラッシュになる。これを避けるため `nonisolated static` で生成し、
    /// クロージャを MainActor 非隔離にする。
    private nonisolated static func makeArtwork(from cgImage: CGImage) -> MPMediaItemArtwork {
        let image = UIImage(cgImage: cgImage)
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
    #endif

    /// Now Playing 情報をクリアする。
    public func clear() {
        #if canImport(MediaPlayer) && os(iOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
    }

    /// リモートコマンド（再生/一時停止・トグル・次/前・シーク）のハンドラを登録する。
    ///
    /// 各コマンドを有効化し、発火のたびに渡したハンドラを対応する `NowPlayingRemoteCommand` で呼ぶ。
    public func observeCommand(_ handler: @escaping @MainActor @Sendable (NowPlayingRemoteCommand) -> Void) {
        #if canImport(MediaPlayer) && os(iOS)
        let center = MPRemoteCommandCenter.shared()

        // addTarget のブロックは OS が任意のスレッドから呼ぶ。`@MainActor` の `handler` を直接呼ぶと
        // actor-executor 不一致でクラッシュするため、ブロックを `@Sendable`（非隔離）にしたうえで
        // MainActor へホップしてから `handler` を呼ぶ。
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { @Sendable _ in
            Task { @MainActor in handler(.play) }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in handler(.pause) }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in handler(.toggle) }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { @Sendable _ in
            Task { @MainActor in handler(.next) }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { @Sendable _ in
            Task { @MainActor in handler(.previous) }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { @Sendable event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = event.positionTime
            Task { @MainActor in handler(.seek(position)) }
            return .success
        }
        #endif
    }
}
