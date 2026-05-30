//
//  CustomVideoPlayer.swift
//  Library
//
//  AVPlayer + AVPlayerLayer による自前の再生ビュー（F-2）と PIP 連携（F-3）。
//
//  AVKit の SwiftUI 製 `VideoPlayer` ではなく、`AVPlayerLayer` を直接管理する構成にすることで、
//  将来的な独自再生コントロール（ミュート切り替え F-7・シーク・PIP 連携 F-3 など）を載せる
//  カスタマイズ余地を確保する。再生レイヤーは UIKit（UIViewController）で実装し、SwiftUI へは
//  UIViewControllerRepresentable でブリッジする。
//
//  PIP（F-3）について:
//  `AVPictureInPictureController` は `AVPlayerLayer` に密結合（システムの PIP は再生レイヤー単位で
//  動く）ため、レイヤーを保持するこの View 層で生成・管理する。バックグラウンド移行・他アプリ操作中の
//  再生継続は、`canStartPictureInPictureAutomaticallyFromInline` による自動 PIP 起動で実現する。
//  （バックグラウンド再生に必要なオーディオセッション設定は VideoPlayerProxy 経由で Infra が担う。）
//

import AVFoundation
import SwiftUI

#if canImport(UIKit)
import AVKit
import UIKit
#endif

/// AVPlayer + AVPlayerLayer による再生ビュー。SwiftUI からはこの View を使う。
struct CustomVideoPlayer: View {

    let player: AVPlayer

    /// PIP（自動起動を含む）を有効化するか。バックグラウンド再生（F-3）の中核。
    var isPictureInPictureEnabled: Bool = true

    var body: some View {
        #if canImport(UIKit)
        PlayerViewControllerRepresentable(
            player: player,
            isPictureInPictureEnabled: isPictureInPictureEnabled
        )
        #else
        // macOS（テストランナー）向けフォールバック。再生対象は iOS のみ。
        Color.black
        #endif
    }
}

#if canImport(UIKit)

/// AVPlayerLayer を管理する UIViewController を SwiftUI へブリッジする。
private struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {

    let player: AVPlayer
    let isPictureInPictureEnabled: Bool

    func makeUIViewController(context: Context) -> PlayerViewController {
        let controller = PlayerViewController(player: player)
        controller.isPictureInPictureEnabled = isPictureInPictureEnabled
        return controller
    }

    func updateUIViewController(_ uiViewController: PlayerViewController, context: Context) {
        // SwiftUI 側で player が差し替わった場合に追従する。
        uiViewController.player = player
        uiViewController.isPictureInPictureEnabled = isPictureInPictureEnabled
    }
}

/// AVPlayerLayer をホストし、PIP コントローラを管理する再生用 UIViewController。
///
/// AVKit の `AVPlayerViewController` ではなく `AVPlayerLayer` を直接扱うことで、
/// 再生面の見た目・オーバーレイ・操作を自由に組み立てられるようにする。
/// PIP は AVPlayerLayer に紐づくため、このレイヤーホストの上で `AVPictureInPictureController` を構築する。
final class PlayerViewController: UIViewController {

    /// 表示中の AVPlayer。ホストビューの AVPlayerLayer に委譲する。
    var player: AVPlayer? {
        get { playerLayerHostView.player }
        set { playerLayerHostView.player = newValue }
    }

    /// PIP（自動起動を含む）を有効化するか。
    var isPictureInPictureEnabled: Bool = true {
        didSet { pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = isPictureInPictureEnabled }
    }

    private let initialPlayer: AVPlayer

    /// AVPlayerLayer に紐づく PIP コントローラ。レイヤー確定後（viewDidLoad）に生成する。
    private var pictureInPictureController: AVPictureInPictureController?

    init(player: AVPlayer) {
        self.initialPlayer = player
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// ルートビューを AVPlayerLayer ホストビューに差し替える。
    override func loadView() {
        view = PlayerLayerHostView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        player = initialPlayer
        setUpPictureInPicture()
    }

    /// AVPlayerLayer から PIP コントローラを構築し、自動 PIP 起動を有効化する。
    ///
    /// 端末が PIP 非対応の場合は何もしない。自動起動を有効にすると、再生中にアプリが
    /// バックグラウンドへ移行した際にシステムが自動で PIP を開始し、再生が継続される（F-3）。
    private func setUpPictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let controller = AVPictureInPictureController(playerLayer: playerLayerHostView.playerLayer)
        controller?.canStartPictureInPictureAutomaticallyFromInline = isPictureInPictureEnabled
        pictureInPictureController = controller
    }

    private var playerLayerHostView: PlayerLayerHostView {
        // loadView で必ず PlayerLayerHostView を設定しているため安全。
        view as! PlayerLayerHostView
    }
}

/// バッキングレイヤーを `AVPlayerLayer` にした UIView。
///
/// `layerClass` を上書きすることで、ビューのレイアウト変化に AVPlayerLayer が自動追従し、
/// 手動での frame 同期が不要になる。PIP コントローラ生成のため、この AVPlayerLayer を公開する。
final class PlayerLayerHostView: UIView {

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    /// 表示する AVPlayer。バッキングの AVPlayerLayer へ委譲する。
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    /// バッキングの AVPlayerLayer。PIP コントローラの構築に用いる。
    var playerLayer: AVPlayerLayer {
        // layerClass で AVPlayerLayer を指定しているため安全。
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // アスペクト比を保ったまま全体を収める（はみ出しなし）。
        playerLayer.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#endif
