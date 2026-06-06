//
//  PictureInPictureClient.swift
//  Infra
//
//  AVPictureInPictureController の唯一の窓口（single source of truth）。
//
//  PIP（F-3）はシステムの再生レイヤー単位（AVPlayerLayer）で動くため、`AVPictureInPictureController` の
//  生成・保持・自動起動フラグの反映をここに閉じ込める。再生アイテムの取得や「どの動画を再生するか」という
//  使う側の都合は持たず、AVPlayerLayer を受け取って PIP を構成するだけに責務を限定する。
//  他の Infra Client（VideoPlayerClient / AudioSessionClient）には依存しない。
//
//  AVPictureInPictureController は iOS/AVKit のみで利用可能なため、テストランナー（macOS）では
//  no-op スタブとし、ビルド整合を保つ（AudioSessionClient の `#if` 作法を踏襲）。
//

import AVFoundation

#if canImport(AVKit) && os(iOS)
import AVKit
#endif

/// AVPictureInPictureController の生成・管理を集約するクライアント。
///
/// `configure(playerLayer:)` で渡された AVPlayerLayer に紐づく PIP コントローラを生成・保持し、
/// 自動 PIP 起動フラグ（`canStartPictureInPictureAutomaticallyFromInline`）を反映する。
/// iOS 以外（テストランナーの macOS）では全 API が no-op。
@MainActor
public final class PictureInPictureClient {

    #if canImport(AVKit) && os(iOS)
    /// AVPlayerLayer に紐づく PIP コントローラ。`configure(playerLayer:)` で生成・差し替えする。
    private var controller: AVPictureInPictureController?
    #endif

    /// 自動 PIP 起動の有効/無効。controller 生成前に設定されても保持し、生成時に反映する。
    private var automaticStartEnabled = true

    public nonisolated init() {}

    /// 渡された AVPlayerLayer に紐づく PIP コントローラを構成する。
    ///
    /// 端末が PIP 非対応なら何もしない。対応端末では新しいコントローラを生成して保持中の
    /// 自動起動フラグを反映する。再呼び出し時は古いコントローラ（と参照していた layer）を差し替える。
    public func configure(playerLayer: AVPlayerLayer) {
        #if canImport(AVKit) && os(iOS)
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let controller = AVPictureInPictureController(playerLayer: playerLayer)
        controller?.canStartPictureInPictureAutomaticallyFromInline = automaticStartEnabled
        self.controller = controller
        #endif
    }

    /// 自動 PIP 起動の有効/無効を設定する。コントローラがあれば即座に反映する。
    public func setAutomaticStartEnabled(_ enabled: Bool) {
        automaticStartEnabled = enabled
        #if canImport(AVKit) && os(iOS)
        controller?.canStartPictureInPictureAutomaticallyFromInline = enabled
        #endif
    }
}
