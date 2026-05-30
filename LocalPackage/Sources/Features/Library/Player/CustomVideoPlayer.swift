//
//  CustomVideoPlayer.swift
//  Library
//
//  AVPlayer + AVPlayerLayer による自前の再生ビュー（F-2）。
//
//  AVKit の SwiftUI 製 `VideoPlayer` ではなく、`AVPlayerLayer` を直接管理する構成にすることで、
//  将来的な独自再生コントロール（ミュート切り替え F-7・シーク・PIP 連携 F-3 など）を載せる
//  カスタマイズ余地を確保する。再生レイヤーは UIKit（UIViewController）で実装し、SwiftUI へは
//  UIViewControllerRepresentable でブリッジする。
//

import AVFoundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// AVPlayer + AVPlayerLayer による再生ビュー。SwiftUI からはこの View を使う。
struct CustomVideoPlayer: View {

    let player: AVPlayer

    var body: some View {
        #if canImport(UIKit)
        PlayerViewControllerRepresentable(player: player)
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

    func makeUIViewController(context: Context) -> PlayerViewController {
        PlayerViewController(player: player)
    }

    func updateUIViewController(_ uiViewController: PlayerViewController, context: Context) {
        // SwiftUI 側で player が差し替わった場合に追従する。
        uiViewController.player = player
    }
}

/// AVPlayerLayer をホストする再生用 UIViewController。
///
/// AVKit の `AVPlayerViewController` ではなく `AVPlayerLayer` を直接扱うことで、
/// 再生面の見た目・オーバーレイ・操作を自由に組み立てられるようにする。
final class PlayerViewController: UIViewController {

    /// 表示中の AVPlayer。ホストビューの AVPlayerLayer に委譲する。
    var player: AVPlayer? {
        get { playerLayerHostView.player }
        set { playerLayerHostView.player = newValue }
    }

    private let initialPlayer: AVPlayer

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
    }

    private var playerLayerHostView: PlayerLayerHostView {
        // loadView で必ず PlayerLayerHostView を設定しているため安全。
        view as! PlayerLayerHostView
    }
}

/// バッキングレイヤーを `AVPlayerLayer` にした UIView。
///
/// `layerClass` を上書きすることで、ビューのレイアウト変化に AVPlayerLayer が自動追従し、
/// 手動での frame 同期が不要になる。
final class PlayerLayerHostView: UIView {

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    /// 表示する AVPlayer。バッキングの AVPlayerLayer へ委譲する。
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    private var playerLayer: AVPlayerLayer {
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
