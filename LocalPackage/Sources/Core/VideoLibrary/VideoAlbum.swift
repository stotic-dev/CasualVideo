//
//  VideoAlbum.swift
//  Core
//
//  写真ライブラリ上のアルバム（コレクション）を表すドメインモデル。
//

import Foundation

/// 写真ライブラリ上のアルバムのドメインモデル（F-6）。
///
/// PhotoKit の `PHAssetCollection` 等の具体型には依存せず、`Core` で完結する値型として定義する。
/// アルバム内の動画は「動的＝再生開始時に最新の内容を取得」するため、ここでは動画そのものは保持せず
/// アルバムの識別子・タイトル・動画件数のみを持つ。
public struct VideoAlbum: Identifiable, Sendable, Hashable {

    /// PhotoKit の `localIdentifier` に対応する一意な識別子。
    public let id: String

    /// アルバムのタイトル。
    public let title: String

    /// アルバム内の動画件数（一覧表示の補助情報）。
    public let videoCount: Int

    /// アルバムを代表するサムネイル用アセットの識別子（一覧の代表画像表示に用いる）。
    ///
    /// 通常はアルバム内で最新の動画。取得できない場合は nil。
    public let thumbnailAssetID: VideoAsset.ID?

    public init(
        id: String,
        title: String,
        videoCount: Int,
        thumbnailAssetID: VideoAsset.ID? = nil
    ) {
        self.id = id
        self.title = title
        self.videoCount = videoCount
        self.thumbnailAssetID = thumbnailAssetID
    }
}
