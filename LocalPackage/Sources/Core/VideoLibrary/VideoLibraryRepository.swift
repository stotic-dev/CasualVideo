//
//  VideoLibraryRepository.swift
//  Core
//
//  写真ライブラリ（PhotoKit）へのアクセスを抽象化する Repository 型定義。
//

import CoreGraphics
import Foundation

/// 写真ライブラリの動画アセットへアクセスするための Repository。
///
/// 抽象化は protocol ではなく struct + クロージャで表現する。
/// 型定義は `Core` に置き、本番実装（`.live`）は `App` が `Infra` を用いて構築する。
public struct VideoLibraryRepository: Sendable {

    /// 現在のアクセス許可状態を返す。
    public var authorizationStatus: @Sendable () async -> VideoLibraryAuthorizationStatus

    /// アクセス許可をリクエストし、リクエスト後の許可状態を返す。
    public var requestAuthorization: @Sendable () async -> VideoLibraryAuthorizationStatus

    /// 写真ライブラリ内の全動画アセットを撮影日の新しい順で取得する。
    public var fetchVideos: @Sendable () async -> [VideoAsset]

    /// 指定アセットのサムネイルを非同期に取得する。
    ///
    /// パフォーマンス配慮のためセル表示時に遅延呼び出しする想定。取得できない場合は nil。
    public var loadThumbnail: @Sendable (_ id: VideoAsset.ID, _ size: CGSize) async -> CGImage?

    public init(
        authorizationStatus: @escaping @Sendable () async -> VideoLibraryAuthorizationStatus,
        requestAuthorization: @escaping @Sendable () async -> VideoLibraryAuthorizationStatus,
        fetchVideos: @escaping @Sendable () async -> [VideoAsset],
        loadThumbnail: @escaping @Sendable (_ id: VideoAsset.ID, _ size: CGSize) async -> CGImage?
    ) {
        self.authorizationStatus = authorizationStatus
        self.requestAuthorization = requestAuthorization
        self.fetchVideos = fetchVideos
        self.loadThumbnail = loadThumbnail
    }
}
