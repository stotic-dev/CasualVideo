//
//  VideoPlayerClient.swift
//  Infra
//
//  AVPlayer による再生エンジンの唯一の窓口（single source of truth）。
//
//  AVPlayer インスタンスを保持し、アイテムの差し替え・再生制御という AVPlayer 単体の操作だけを
//  ここに閉じ込める。再生アイテムの取得（PhotoKit 等）や「どの動画を再生するか」という使う側の
//  都合は持たない。複数 Infra を組み合わせた再生フロー（取得 → 差し替え → 再生）の組み立ては
//  `App` が `VideoPlayerProxy` の本番実装として担う。
//

import AVFoundation
import Foundation

/// AVPlayer の操作を集約する再生エンジンクライアント。
///
/// `AVPlayer` は単一インスタンスを保持し、`replaceCurrentItem` でアイテムを差し替える。
/// 全操作をメインアクター上で行うことで、`AVPlayer` への同時アクセスを避ける。
/// （`@MainActor` final class は暗黙的に `Sendable` となり、Proxy のクロージャから安全に参照できる。）
@MainActor
public final class VideoPlayerClient {

    /// 再生レイヤー（AVPlayerLayer）へバインドするための AVPlayer。
    public let player = AVPlayer()

    /// 現在再生中アイテムの再生完了通知の購読トークン。
    private var didPlayToEndObserver: NSObjectProtocol?

    /// 再生完了時に呼び出すハンドラ（プレイリストの自動遷移に使う / F-4）。
    private var didPlayToEndHandler: (() -> Void)?

    /// 定期的な再生時刻監視の購読トークン（シークバー更新 / F-6）。
    private var periodicTimeObserver: Any?

    public nonisolated init() {}

    /// 再生アイテムを差し替える。差し替えたアイテムの再生完了通知を購読し直す。
    ///
    /// アイテムの取得元（PhotoKit など）は問わない。呼び出し側が用意した `AVPlayerItem` を受け取り、
    /// AVPlayer へ載せ替えるだけに責務を限定する。
    public func replaceCurrentItem(_ item: sending AVPlayerItem) {
        removeDidPlayToEndObserver()
        player.replaceCurrentItem(with: item)
        didPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.didPlayToEndHandler?()
            }
        }
    }

    /// 再生を開始・再開する。
    public func play() {
        player.play()
    }

    /// 再生を一時停止する。
    public func pause() {
        player.pause()
    }

    /// 音声ミュートを切り替える。
    public func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    /// 現在再生中アイテムの再生完了を購読する。再生完了のたびに `handler` が呼ばれる。
    ///
    /// プレイリストの「1 動画の再生終了で次へ自動遷移」（F-4）の起点となる。
    public func observeDidPlayToEnd(_ handler: @escaping () -> Void) {
        didPlayToEndHandler = handler
    }

    /// 指定秒へシークする。シークバー操作（F-6）からの再生位置変更に用いる。
    public func seek(to seconds: TimeInterval) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 再生時刻を一定間隔で購読する。更新のたびに「現在位置（秒）・総再生時間（秒）」を `handler` へ渡す。
    ///
    /// シークバーの位置・長さ表示（F-6）の起点となる。総再生時間が未確定なら 0 を渡す。
    public func observeTime(
        interval: TimeInterval = 0.5,
        handler: @escaping @MainActor @Sendable (_ currentTime: TimeInterval, _ duration: TimeInterval) -> Void
    ) {
        removePeriodicTimeObserver()
        let observerInterval = CMTime(seconds: interval, preferredTimescale: 600)
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: observerInterval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                let duration = self?.player.currentItem?.duration.seconds ?? 0
                let validDuration = (duration.isFinite ? duration : 0)
                handler(time.seconds, validDuration)
            }
        }
    }

    // MARK: - Private

    private func removePeriodicTimeObserver() {
        guard let periodicTimeObserver else { return }
        player.removeTimeObserver(periodicTimeObserver)
        self.periodicTimeObserver = nil
    }

    private func removeDidPlayToEndObserver() {
        guard let didPlayToEndObserver else { return }
        NotificationCenter.default.removeObserver(didPlayToEndObserver)
        self.didPlayToEndObserver = nil
    }
}
