//
//  VideoAsset.swift
//  Core
//
//  写真ライブラリ上の動画アセットを表すドメインモデル。
//

import Foundation

/// 写真ライブラリ上の動画アセットのドメインモデル。
///
/// PhotoKit の `PHAsset` 等の具体型には依存せず、`Core` で完結する値型として定義する。
public struct VideoAsset: Identifiable, Sendable, Hashable {

    /// PhotoKit の `localIdentifier` に対応する一意な識別子。
    public let id: String

    /// 再生時間。
    public let duration: TimeInterval

    /// 撮影日（取得できない場合は nil）。
    public let creationDate: Date?

    /// iCloud 上にあり端末へ未ダウンロードかどうか。
    public let isInCloud: Bool

    public init(
        id: String,
        duration: TimeInterval,
        creationDate: Date?,
        isInCloud: Bool
    ) {
        self.id = id
        self.duration = duration
        self.creationDate = creationDate
        self.isInCloud = isInCloud
    }
}
