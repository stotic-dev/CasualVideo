//
//  CustomVideoPlayer.swift
//  Library
//
//  AVPlayerLayer による自前の再生ビュー（F-2）と PIP 連携（F-3）。
//
//  AVKit の SwiftUI 製 `VideoPlayer` ではなく、`AVPlayerLayer` を直接管理する構成にすることで、
//  将来的な独自再生コントロール（ミュート切り替え F-7・シーク・PIP 連携 F-3 など）を載せる
//  カスタマイズ余地を確保する。再生レイヤーは UIKit（UIViewController）で実装し、SwiftUI へは
//  UIViewControllerRepresentable でブリッジする。
//
//  再生エンジン（AVPlayer）と PIP コントローラ（AVPictureInPictureController）は Features 層では扱わない。
//  この View が所有するのは描画レイヤー（AVPlayerLayer）のみで、player のバインドと PIP の構成は
//  `VideoPlayerProxy`（Core）のクロージャ経由で App / Infra へ委譲する。
//  - `attachPlayerLayer(layer)`: 所有する AVPlayerLayer へ player をバインドし PIP を構成する。
//  - `setPictureInPictureEnabled(_:)`: 自動 PIP 起動（F-3）の有効/無効を切り替える。
//

import Core
import SwiftUI

#if canImport(UIKit)
import AVFoundation
import UIKit
#endif

/// AVPlayerLayer による再生ビュー。SwiftUI からはこの View を使う。
///
/// 再生エンジンの参照は持たず、`VideoPlayerProxy` から得たクロージャ経由で描画面を構成する。
struct CustomVideoPlayer: View {

    @Environment(\.videoPlayerProxy) private var playerProxy

    /// PIP（自動起動を含む）を有効化するか。バックグラウンド再生（F-3）の中核。
    var isPictureInPictureEnabled: Bool = true

    var body: some View {
        #if canImport(UIKit)
        PlayerViewControllerRepresentable(
            attachPlayerLayer: playerProxy.attachPlayerLayer,
            setPictureInPictureEnabled: playerProxy.setPictureInPictureEnabled,
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

    /// 所有する AVPlayerLayer へ player をバインドし PIP を構成するクロージャ（Proxy 経由）。
    let attachPlayerLayer: @MainActor (AVPlayerLayer) -> Void
    /// 自動 PIP 起動の有効/無効を切り替えるクロージャ（Proxy 経由）。
    let setPictureInPictureEnabled: @MainActor (Bool) -> Void
    let isPictureInPictureEnabled: Bool

    func makeUIViewController(context: Context) -> PlayerViewController {
        let controller = PlayerViewController(
            attachPlayerLayer: attachPlayerLayer,
            setPictureInPictureEnabled: setPictureInPictureEnabled
        )
        controller.isPictureInPictureEnabled = isPictureInPictureEnabled
        return controller
    }

    func updateUIViewController(_ uiViewController: PlayerViewController, context: Context) {
        uiViewController.isPictureInPictureEnabled = isPictureInPictureEnabled
    }
}

/// AVPlayerLayer をホストする再生用 UIViewController。
///
/// AVKit の `AVPlayerViewController` ではなく `AVPlayerLayer` を直接扱うことで、
/// 再生面の見た目・オーバーレイ・操作を自由に組み立てられるようにする。
/// 再生エンジン（AVPlayer）や PIP コントローラは保持せず、所有する AVPlayerLayer を
/// `VideoPlayerProxy` のクロージャへ渡して player バインド・PIP 構成を委譲する。
final class PlayerViewController: UIViewController {

    /// PIP（自動起動を含む）を有効化するか。
    var isPictureInPictureEnabled: Bool = true {
        didSet { setPictureInPictureEnabled(isPictureInPictureEnabled) }
    }

    /// 所有する AVPlayerLayer へ player をバインドし PIP を構成するクロージャ（Proxy 経由）。
    private let attachPlayerLayer: @MainActor (AVPlayerLayer) -> Void
    /// 自動 PIP 起動の有効/無効を切り替えるクロージャ（Proxy 経由）。
    private let setPictureInPictureEnabled: @MainActor (Bool) -> Void

    init(
        attachPlayerLayer: @escaping @MainActor (AVPlayerLayer) -> Void,
        setPictureInPictureEnabled: @escaping @MainActor (Bool) -> Void
    ) {
        self.attachPlayerLayer = attachPlayerLayer
        self.setPictureInPictureEnabled = setPictureInPictureEnabled
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
        // 所有する描画レイヤーへ player をバインドし PIP を構成する（手順は Proxy / App / Infra が担う）。
        attachPlayerLayer(playerLayerHostView.playerLayer)
        setPictureInPictureEnabled(isPictureInPictureEnabled)
    }

    private var playerLayerHostView: PlayerLayerHostView {
        // loadView で必ず PlayerLayerHostView を設定しているため安全。
        view as! PlayerLayerHostView
    }
}

/// バッキングレイヤーを `AVPlayerLayer` にした UIView。
///
/// `layerClass` を上書きすることで、ビューのレイアウト変化に AVPlayerLayer が自動追従し、
/// 手動での frame 同期が不要になる。所有する AVPlayerLayer を公開し、player バインド・PIP 構成に用いる。
final class PlayerLayerHostView: UIView {

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    /// バッキングの AVPlayerLayer。player バインド・PIP 構成（Proxy 経由）に用いる。
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
