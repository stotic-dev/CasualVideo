//
//  CastProxy+Live.swift
//  App
//
//  CastProxy の本番実装（Impl）。Infra の Cast SDK 窓口・ローカル HTTP サーバ・PhotoKit を
//  組み合わせて、ローカル動画を Chromecast へ引き継ぐオーケストレーションを assemble する。
//

import Core
import Infra
import Foundation

extension CastProxy {

    /// 本番インスタンスを構築する。
    ///
    /// `loadAndPlay` は「PhotoKit からローカル動画を書き出し → ローカル HTTP サーバで配信 →
    /// 得られた URL を Cast へロード」という複数 Infra をまたぐ手順を組み立てる
    /// （docs-internal/architecture.md「複数 Infra をまたぐオーケストレーションは `.live` で組み立てる」）。
    ///
    /// - Parameters:
    ///   - castClient: GoogleCast SDK の窓口。
    ///   - mediaServer: ローカル動画を LAN 上で HTTP 配信するサーバ。
    ///   - photoLibraryClient: PhotoKit の窓口（再生用ファイルの書き出し元）。
    static func live(
        castClient: CastClient,
        mediaServer: LocalMediaServer,
        photoLibraryClient: PhotoLibraryClient
    ) -> CastProxy {
        CastProxy(
            // 起動時に Cast コンテキストを初期化し、ローカル HTTP サーバの待受も開始する。
            setUp: {
                castClient.setUp()
                mediaServer.start()
            },
            // セッション接続状態（Infra の Bool）を Core の状態へマッピングして橋渡しする。
            observeSessionState: { handler in
                castClient.observeSessionState { isConnected in
                    handler(isConnected ? .connected : .disconnected)
                }
            },
            // ローカル動画を Cast デバイスへ引き継ぐ手順をここで組み立てる。
            loadAndPlay: { id in
                // 1. PhotoKit からローカルファイルへ書き出す。
                guard let exported = await photoLibraryClient.exportVideoFile(localIdentifier: id) else {
                    return false
                }
                // 2. 書き出したファイルをローカル HTTP サーバへ登録し、デバイスが取得可能な URL を得る。
                guard let url = mediaServer.register(
                    fileURL: exported.fileURL,
                    mimeType: exported.mimeType
                ) else {
                    return false
                }
                // 3. その URL を Cast デバイスへロードして再生する（SDK 操作は MainActor 上）。
                return await MainActor.run {
                    castClient.loadMedia(url: url, contentType: exported.mimeType, title: "CasualVideo")
                }
            },
            isConnected: {
                castClient.isConnected()
            },
            // Cast デバイス側の再生状態（Infra のスナップショット）を Core の状態へマッピングして橋渡しする。
            observeRemoteState: { handler in
                castClient.observeRemoteState { snapshot in
                    handler(
                        CastPlaybackState(
                            progress: PlaybackProgress(currentTime: snapshot.position, duration: snapshot.duration),
                            isPlaying: snapshot.isPlaying
                        )
                    )
                }
            },
            play: { castClient.playRemote() },
            pause: { castClient.pauseRemote() },
            seek: { castClient.seekRemote(to: $0) }
        )
    }
}
