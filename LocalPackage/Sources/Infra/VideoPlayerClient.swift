//
//  VideoPlayerClient.swift
//  Infra
//
//  AVPlayer による再生エンジンの唯一の窓口（single source of truth）。
//
//  AVPlayer インスタンスを保持し、アイテムの読み込み（PhotoKit 経由）・差し替え・再生制御を
//  ここに閉じ込める。`App` がこれを参照して `VideoPlayerProxy` の本番実装を組み立てる。
//

import AVFoundation
import Foundation

/// AVPlayer の操作を集約する再生エンジンクライアント。
///
/// `AVPlayer` は単一インスタンスを保持し、`replaceCurrentItem` でアイテムを差し替える。
/// 全操作をメインアクター上で行うことで、`AVPlayer` への同時アクセスを避ける。
/// （`@MainActor` final class は暗黙的に `Sendable` となり、Proxy のクロージャから安全に参照できる。）
@MainActor
public final class VideoPlayerClient {

    /// 再生レイヤー（AVPlayerLayer）へバインドするための AVPlayer。
    public let player = AVPlayer()

    /// アイテム読み込みのための PhotoKit クライアント。
    private let photoLibrary = PhotoLibraryClient()

    public nonisolated init() {}

    /// 指定アセットの動画を読み込んで差し替え、再生を開始する。読み込み成否を返す。
    ///
    /// iCloud 上の動画も対象とする（`PhotoLibraryClient.loadPlayerItem` がネットワークアクセスを許可）。
    public func loadAndPlay(localIdentifier: String) async -> Bool {
        guard let item = await photoLibrary.loadPlayerItem(localIdentifier: localIdentifier) else {
            return false
        }
        player.replaceCurrentItem(with: item)
        player.play()
        return true
    }

    /// 再生を再開する。
    public func play() {
        player.play()
    }

    /// 再生を一時停止する。
    public func pause() {
        player.pause()
    }

    /// 音声ミュートを切り替える。
    public func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }
}
