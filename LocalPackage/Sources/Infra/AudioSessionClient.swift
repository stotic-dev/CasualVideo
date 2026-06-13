//
//  AudioSessionClient.swift
//  Infra
//
//  AVAudioSession 設定の唯一の窓口（single source of truth）。
//
//  PIP・バックグラウンド再生（F-3）には、アプリの AVAudioSession を `.playback` カテゴリで
//  アクティブ化する必要がある。この「プロセス外（システムのオーディオセッション）」への設定を
//  ここに閉じ込め、`App` がこれを参照して `VideoPlayerProxy` の本番実装へ組み込む。
//

#if canImport(AVFAudio) && os(iOS)
import AVFAudio
#endif

/// アプリのオーディオセッション設定を集約するクライアント。
///
/// バックグラウンド・他アプリ操作中でも再生を継続できるよう、`.playback` カテゴリで
/// セッションをアクティブ化する。iOS 以外（テストランナーの macOS）では no-op。
public struct AudioSessionClient: Sendable {

    public init() {}

    /// バックグラウンド再生・PIP のためにオーディオセッションを `.playback` で構成・アクティブ化する。
    ///
    /// 失敗しても再生自体は継続可能なため、エラーは握りつぶす（ラフな"ながら見"体験を優先）。
    public func activatePlayback() {
        #if canImport(AVFAudio) && os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        #endif
    }

    /// オーディオセッションを非アクティブ化する。閉じる導線での再生セッション破棄に用いる。
    ///
    /// `.playback` セッションを `setActive(false)` で解除する。失敗しても致命的ではないため
    /// エラーは握りつぶす（ラフな"ながら見"体験を優先）。iOS 以外（macOS）では no-op。
    public func deactivate() {
        #if canImport(AVFAudio) && os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false)
        #endif
    }
}
