//
//  CastProxy+SystemRouting.swift
//  App
//
//  CastProxy の iOS 27 `AVSystemRouting` 実装。`SystemRouteCastClient`・ローカル HTTP サーバ・
//  PhotoKit を組み合わせ、ルート選択時にローカル動画を第三者デバイスへ送出する手順を assemble する。
//
//  GoogleCast 経路（`CastProxy.live`）との違い:
//  - メディアのロードはルート選択（`.activate`）ハンドラ内で完結する（Apple 推奨フロー）。そのため
//    接続後に呼ばれる `loadAndPlay(id)` は no-op（true）とし、二重ロードを避ける。
//  - 「いま再生中アセット」をハンドラ内で必要とするため、`setNowPlayingAssetProvider` で
//    再生セッション（`PlaybackStore`）からアセット ID プロバイダを受け取り、Client へ橋渡しする。
//

import Core
import Infra
import Foundation

extension CastProxy {

    /// `AVSystemRouting` を用いた本番インスタンスを構築する。
    ///
    /// - Parameters:
    ///   - client: `AVSystemRouting` の窓口。
    ///   - mediaServer: ローカル動画を LAN 上で HTTP 配信するサーバ。
    ///   - photoLibraryClient: PhotoKit の窓口（再生用ファイルの書き出し元）。
    static func systemRouting(
        client: SystemRouteCastClient,
        mediaServer: LocalMediaServer,
        photoLibraryClient: PhotoLibraryClient
    ) -> CastProxy {
        // アセット ID から「PhotoKit 書き出し → ローカル HTTP 配信 → 配信メディア」を解決するクロージャ。
        // ルート選択時に Client がこれを呼び、得た URL でセッションを開始する。
        let mediaResolver: @Sendable (String) async -> ResolvedCastMedia? = { id in
            guard let exported = await photoLibraryClient.exportVideoFile(localIdentifier: id) else {
                return nil
            }
            guard let url = mediaServer.register(
                fileURL: exported.fileURL,
                mimeType: exported.mimeType
            ) else {
                return nil
            }
            return ResolvedCastMedia(url: url, mimeType: exported.mimeType, title: "CasualVideo")
        }

        return CastProxy(
            // 起動時にルート監視を開始し、ローカル HTTP サーバの待受も開始する。
            setUp: {
                client.setMediaResolver(mediaResolver)
                client.setUp()
                mediaServer.start()
            },
            // セッション接続状態（Infra の Bool）を Core の状態へマッピングして橋渡しする。
            observeSessionState: { handler in
                client.observeSessionState { isConnected in
                    handler(isConnected ? .connected : .disconnected)
                }
            },
            // メディアは `.activate` ハンドラ内で既にロード済みのため no-op（二重ロード回避）。
            loadAndPlay: { _ in true },
            isConnected: {
                client.isConnected()
            },
            // 再生セッションのアセット ID プロバイダを Client へ橋渡しする。
            setNowPlayingAssetProvider: { provider in
                client.setAssetIDProvider { provider() }
            }
        )
    }
}
