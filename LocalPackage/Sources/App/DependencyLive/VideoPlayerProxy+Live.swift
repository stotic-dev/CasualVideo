//
//  VideoPlayerProxy+Live.swift
//  App
//
//  複数の Infra Client を組み合わせて VideoPlayerProxy の本番インスタンスを組み立てる。
//
//  「どの動画を再生するか（VideoAsset.ID）」という使う側の都合を起点に、
//  PhotoKit（PhotoLibraryClient）で再生アイテムを取得し、AVPlayer（VideoPlayerClient）へ載せ替える、
//  という複数 Infra をまたぐオーケストレーションはこの assemble 層が担う。
//  各 Infra Client 自身は互いを知らず、それぞれの単一責務（PhotoKit / AVPlayer）に閉じる。
//

import Core
import Infra

extension VideoPlayerProxy {

    /// AVPlayer 再生エンジン（`VideoPlayerClient`）と写真ライブラリ（`PhotoLibraryClient`）を
    /// 組み合わせた本番インスタンス。
    ///
    /// - Parameters:
    ///   - playerClient: AVPlayer の操作窓口。アイテムの差し替え・再生制御のみを担う。
    ///   - photoLibraryClient: PhotoKit の窓口。`VideoAsset.ID` から再生用 `AVPlayerItem` を取得する。
    ///   - audioSession: バックグラウンド再生・PIP（F-3）用のオーディオセッション窓口。
    ///
    /// `VideoPlayerClient` は `@MainActor` final class（= Sendable）、`PhotoLibraryClient` /
    /// `AudioSessionClient` は値型（Sendable）のため、Proxy のクロージャから安全に参照できる。
    @MainActor
    static func live(
        playerClient: VideoPlayerClient,
        photoLibraryClient: PhotoLibraryClient = PhotoLibraryClient(),
        audioSession: AudioSessionClient = AudioSessionClient(),
        pictureInPictureClient: PictureInPictureClient = PictureInPictureClient(),
    ) -> VideoPlayerProxy {
        return VideoPlayerProxy(
            player: { playerClient.player },
            // 描画レイヤーへの player バインド（VideoPlayerClient）→ その layer で PIP 構成
            // （PictureInPictureClient）という複数 Infra をまたぐ描画面セットアップをここで組み立てる。
            attachPlayerLayer: { layer in
                layer.player = playerClient.player
                pictureInPictureClient.configure(playerLayer: layer)
            },
            // 自動 PIP 起動（F-3）の有効/無効を PIP Client へ委譲。
            setPictureInPictureEnabled: { pictureInPictureClient.setAutomaticStartEnabled($0) },
            // 取得（PhotoKit）→ 差し替え → 再生、という複数 Infra をまたぐ手順をここで組み立てる。
            loadAndPlay: { id in
                guard let item = await photoLibraryClient.loadPlayerItem(localIdentifier: id) else {
                    return false
                }
                await playerClient.replaceCurrentItem(item)
                await playerClient.play()
                return true
            },
            play: { playerClient.play() },
            pause: { playerClient.pause() },
            setMuted: { playerClient.setMuted($0) },
            // 再生速度（F-7）を AVPlayer 窓口へ委譲。defaultRate により item 差し替え後も維持される。
            setRate: { playerClient.setRate($0) },
            // バックグラウンド再生・PIP（F-3）のためのオーディオセッション設定を Infra へ委譲。
            prepareForBackgroundPlayback: { audioSession.activatePlayback() },
            // プレイリスト連続再生（F-4）のための再生完了購読を Infra へ委譲。
            observeDidPlayToEnd: { playerClient.observeDidPlayToEnd($0) },
            // シークバー操作（F-6）のシークを AVPlayer 窓口へ委譲。
            seek: { playerClient.seek(to: $0) },
            // シークバー表示（F-6）のための再生時刻監視を Infra へ委譲し、ドメイン型へ詰め替える。
            observeProgress: { handler in
                playerClient.observeTime { currentTime, duration in
                    handler(PlaybackProgress(currentTime: currentTime, duration: duration))
                }
            }
        )
    }
}
