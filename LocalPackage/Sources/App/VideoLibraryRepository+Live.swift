//
//  VideoLibraryRepository+Live.swift
//  App
//
//  Infra（PhotoLibraryClient）を用いて VideoLibraryRepository の本番インスタンスを組み立てる。
//

import Core
import Infra

extension VideoLibraryRepository {

    /// PhotoKit を用いた本番インスタンス。
    static func live(client: PhotoLibraryClient = PhotoLibraryClient()) -> VideoLibraryRepository {
        VideoLibraryRepository(
            authorizationStatus: {
                client.currentAuthorization().toDomain
            },
            requestAuthorization: {
                await client.requestAuthorization().toDomain
            },
            fetchVideos: {
                client.fetchVideos().map(\.toDomain)
            },
            loadThumbnail: { id, size in
                await client.loadThumbnail(localIdentifier: id, size: size)
            }
        )
    }
}

extension PhotoLibraryAuthorization {
    /// Infra の許可状態を Core のドメインモデルへ変換する。
    var toDomain: VideoLibraryAuthorizationStatus {
        switch self {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        }
    }
}

extension PhotoVideoAsset {
    /// Infra の動画情報を Core のドメインモデルへ変換する。
    var toDomain: VideoAsset {
        VideoAsset(
            id: localIdentifier,
            duration: duration,
            creationDate: creationDate,
            isInCloud: isInCloud
        )
    }
}
