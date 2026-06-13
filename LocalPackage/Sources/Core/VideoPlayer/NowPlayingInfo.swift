//
//  NowPlayingInfo.swift
//  Core
//
//  ロック画面・コントロールセンターの Now Playing 表示（F-5）のためのドメイン型。
//

import Foundation

/// Now Playing（ロック画面 / コントロールセンター）に表示する再生情報。
///
/// `PlaybackProgress` と同じく、再生エンジンやシステム（MediaPlayer）の型は扱わない純粋値型。
/// アートワーク（画像）は UI / プロセス外リソースのため、ここでは画像そのものではなく
/// 参照用の `assetID`（`VideoAsset.ID`）のみを保持する。実際の画像取得は `App` の assemble 層が担う。
public struct NowPlayingInfo: Sendable, Hashable {

    /// 表示タイトル（CasualVideo では "CasualVideo" 固定）。
    public var title: String

    /// 総再生時間（秒）。
    public var duration: TimeInterval

    /// 現在の再生位置（秒）。
    public var elapsedTime: TimeInterval

    /// 再生中かどうか（再生レート 1.0 / 0.0 の判断に用いる）。
    public var isPlaying: Bool
    
    /// 再生中のレート
    public var rate: PlaybackRate

    /// アートワーク取得の参照に用いる現在アセットの ID（無ければ nil）。
    public var assetID: VideoAsset.ID?

    public init(
        title: String,
        duration: TimeInterval,
        elapsedTime: TimeInterval,
        isPlaying: Bool,
        rate: PlaybackRate,
        assetID: VideoAsset.ID?
    ) {
        self.title = title
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.isPlaying = isPlaying
        self.rate = rate
        self.assetID = assetID
    }
}
