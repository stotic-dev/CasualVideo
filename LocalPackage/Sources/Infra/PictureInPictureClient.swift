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
    /// PIP 開始完了を closure へ転送するデリゲート。手動開始（`startPictureInPicture`）の完了検知に用いる。
    /// nonisolated init を保つため、メインアクター隔離されたこのインスタンスは遅延生成する。
    private lazy var delegate = PictureInPictureDelegate()
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
        controller?.delegate = delegate
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

    /// PIP を手動で開始する。コントロールの PIP ボタンからの明示的な遷移に用いる。
    ///
    /// 開始が実際に完了したタイミングで `onDidStart` を呼ぶ。再生画面（モーダル）を閉じる前に
    /// PIP が立ち上がったことを保証するため、開始要求の直後ではなくデリゲートの完了通知を起点とする。
    /// PIP 非対応・開始不可（`isPictureInPicturePossible == false`）の場合は何もしない。
    public func startPictureInPicture(onDidStart: @escaping @MainActor () -> Void) {
        #if canImport(AVKit) && os(iOS)
        guard let controller, controller.isPictureInPicturePossible else { return }
        delegate.onDidStart = onDidStart
        controller.startPictureInPicture()
        #endif
    }

    /// PIP の「戻る（restore）」要求を購読する。復帰ボタンが押されるたびに `handler` が呼ばれる。
    ///
    /// `handler` は閉じていた UI（再生画面）を再提示する責務を担う。システムへの完了通知
    /// （`completionHandler(true)`）は再提示要求の直後に Infra 側で代行するため、`handler` は
    /// 完了ハンドラを意識しない。
    public func observePictureInPictureRestore(_ handler: @escaping @MainActor () -> Void) {
        #if canImport(AVKit) && os(iOS)
        delegate.onRestore = handler
        #endif
    }
}

#if canImport(AVKit) && os(iOS)
/// AVPictureInPictureController の開始完了を closure へ転送するデリゲート。
///
/// `PictureInPictureClient` は値管理に専念させ、NSObject 由来のデリゲート責務をこの小さな
/// 転送オブジェクトへ分離する。AVKit のデリゲートはメインアクター隔離前提のため `@MainActor`。
@MainActor
private final class PictureInPictureDelegate: NSObject, @MainActor AVPictureInPictureControllerDelegate {

    /// PIP 開始完了時に一度だけ呼ぶ closure。
    var onDidStart: (@MainActor () -> Void)?

    /// PIP の「戻る（restore）」要求時に呼ぶ closure。閉じていた UI の再提示を担う。
    var onRestore: (@MainActor () -> Void)?

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        onDidStart?()
        onDidStart = nil
    }

    /// PIP 小窓の復帰ボタンが押されたときに呼ばれる。閉じていた UI を再提示し、完了を通知する。
    ///
    /// 再提示（`onRestore`）は状態更新（モーダル再提示）として行い、その直後に
    /// `completionHandler(true)` を呼んでシステムへ UI 復帰の完了を伝える。
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        guard let onRestore else {
            completionHandler(false)
            return
        }
        onRestore()
        completionHandler(true)
    }
}
#endif
