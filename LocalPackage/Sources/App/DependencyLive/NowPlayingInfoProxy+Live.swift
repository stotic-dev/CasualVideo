//
//  NowPlayingInfoProxy+Live.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/06.
//

import Core
import Infra
import Foundation

/// Now Playing のアートワーク再取得を抑制するための、直近アセット ID を保持する小さな holder。
///
/// `updateNowPlayingInfo` は progress ティックごとに高頻度で呼ばれるため、毎回サムネイルを
/// 取得すると無駄が大きい。アセットが切り替わった（ID が変化した）ときのみ取得するよう、
/// 直近の ID をここで覚えておく。`@MainActor` に閉じ、Proxy のクロージャから安全に参照する。
@MainActor
private final class NowPlayingArtworkState {
    var lastAssetID: VideoAsset.ID?
}

extension NowPlayingInfoProxy {
    @MainActor
    static func live(
        nowPlayingInfoClient: NowPlayingInfoClient = NowPlayingInfoClient(),
        photoLibraryClient: PhotoLibraryClient = PhotoLibraryClient(),
    ) -> Self {
        // Now Playing のアートワーク再取得を抑制するための直近アセット ID 保持先。
        let artworkState = NowPlayingArtworkState()
        // アートワーク取得サイズ（ロック画面・コントロールセンター向けの中間解像度）。
        let artworkSize = CGSize(width: 600, height: 600)
        return .init(
            // Now Playing 情報（F-5）の更新。テキスト系は即時反映し、アートワーク（動画サムネイル）は
            // アセットが切り替わったときのみ PhotoKit から非同期取得して設定する。
            // 「Now Playing 反映（MediaPlayer）＋ サムネイル取得（PhotoKit）」という複数 Infra をまたぐ
            // 手順をこの assemble 層で組み立てる。各 Infra Client は単一責務に閉じる。
            updateNowPlayingInfo: { info in
                let rate = info.isPlaying ? 1.0 : 0.0
                nowPlayingInfoClient.update(
                    title: info.title,
                    duration: info.duration,
                    elapsedTime: info.elapsedTime,
                    rate: rate,
                    artwork: nil
                )
                // アセットが変わったときのみアートワークを取得し直す（毎ティックの再取得を避ける）。
                guard info.assetID != artworkState.lastAssetID else { return }
                artworkState.lastAssetID = info.assetID
                guard let assetID = info.assetID else { return }
                Task { @MainActor in
                    let image = await photoLibraryClient.loadThumbnail(
                        localIdentifier: assetID,
                        size: artworkSize
                    )
                    // 取得中にアセットがさらに切り替わっていたら破棄する。
                    guard artworkState.lastAssetID == assetID else { return }
                    nowPlayingInfoClient.update(
                        title: info.title,
                        duration: info.duration,
                        elapsedTime: info.elapsedTime,
                        rate: rate,
                        artwork: image
                    )
                }
            },
            // Now Playing 情報のクリア（F-5）を Infra へ委譲し、直近アセット ID もリセットする。
            clearNowPlayingInfo: {
                artworkState.lastAssetID = nil
                nowPlayingInfoClient.clear()
            },
            // リモートコマンド（F-5）の購読。Infra ローカルのコマンド種別を Core 型へマッピングして橋渡しする。
            observeRemoteCommand: { handler in
                nowPlayingInfoClient.observeCommand { command in
                    handler(command.toDomain())
                }
            }
        )
    }
}

extension NowPlayingRemoteCommand {

    /// Infra ローカルのコマンド種別を `Core` の `RemoteCommand` へ変換する。
    fileprivate func toDomain() -> RemoteCommand {
        switch self {
        case .play: .play
        case .pause: .pause
        case .toggle: .toggle
        case .next: .next
        case .previous: .previous
        case .seek(let time): .seek(time)
        }
    }
}
