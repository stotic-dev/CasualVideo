//
//  PlaylistStore.swift
//  Core
//
//  プレイリスト連続再生（F-4）＋ シャッフル / リピート（F-5）のドメイン状態と再生制御を担う Store。
//

import Foundation
import Observation

/// プレイリストの連続再生・シャッフル・リピートを管理する Store。
///
/// 「再生対象の動画一覧」「再生順序」「現在の再生位置」を保持し、`VideoPlayerProxy` を介して再生する。
/// 1 動画の再生終了で次の動画へ自動遷移する（F-4 / requirements 3.3）。
/// 再生順序（連続 / シャッフル）とリピート（off / all / one）を切り替えられる（F-5 / requirements 3.2）。
///
/// - Note: 特定画面に依存しないドメイン状態のみを持つ（UI 型は扱わない）。再生操作は抽象（`VideoPlayerProxy`）へ委譲する。
@Observable
@MainActor
public final class PlaylistStore {

    /// 連続再生対象の動画一覧（プレイリストの並び順そのもの）。
    public private(set) var playlist: [VideoAsset] = []

    /// 再生順序モード（連続 / シャッフル）。
    public private(set) var playbackOrder: PlaybackOrder

    /// リピートモード（off / all / one）。
    public private(set) var repeatMode: RepeatMode

    private let playerProxy: VideoPlayerProxy

    /// `playlist` のインデックスを再生する順に並べた配列。シャッフル時はここが入れ替わる。
    private var order: [Int] = []

    /// `order` 内での現在位置。未再生時は `nil`。
    private var orderPosition: Int?

    /// 再生完了オブザーバを一度だけ登録したかどうか。
    private var hasObservedDidPlayToEnd = false

    public init(
        playerProxy: VideoPlayerProxy,
        playbackOrder: PlaybackOrder = .sequential,
        repeatMode: RepeatMode = .off
    ) {
        self.playerProxy = playerProxy
        self.playbackOrder = playbackOrder
        self.repeatMode = repeatMode
    }

    /// 現在再生中の動画のインデックス（`playlist` 上の位置）。未再生時は `nil`。
    public var currentIndex: Int? {
        guard let orderPosition, order.indices.contains(orderPosition) else { return nil }
        return order[orderPosition]
    }

    /// 現在再生中の動画。
    public var currentAsset: VideoAsset? {
        guard let currentIndex, playlist.indices.contains(currentIndex) else { return nil }
        return playlist[currentIndex]
    }

    /// 現在の再生位置（再生順での 1 始まり）。未再生時は `nil`。
    public var currentPosition: Int? {
        orderPosition.map { $0 + 1 }
    }

    /// プレイリスト内の総数。
    public var totalCount: Int {
        playlist.count
    }

    /// 次の動画へ進めるか。リピート時（all / one）は要素があれば常に進める（末尾でも先頭へ戻る）。
    public var canPlayNext: Bool {
        guard let orderPosition else { return false }
        if repeatMode != .off { return !order.isEmpty }
        return orderPosition + 1 < order.count
    }

    /// 前の動画へ戻れるか。リピート時（all / one）は要素があれば常に戻れる（先頭でも末尾へ回る）。
    public var canPlayPrevious: Bool {
        guard let orderPosition else { return false }
        if repeatMode != .off { return !order.isEmpty }
        return orderPosition - 1 >= 0
    }

    /// 指定したプレイリストを、指定インデックスから再生する。
    ///
    /// - Parameters:
    ///   - assets: 再生対象の動画一覧。
    ///   - startIndex: 再生を開始する `playlist` 上のインデックス（既定は先頭）。
    public func start(playlist assets: [VideoAsset], from startIndex: Int = 0) async {
        guard !assets.isEmpty else { return }
        playlist = assets
        registerDidPlayToEndIfNeeded()
        let index = assets.indices.contains(startIndex) ? startIndex : 0
        let position = rebuildOrder(startingFrom: index)
        await play(orderPosition: position)
    }

    /// 次の動画へ手動で進める。リピート時は末尾から先頭へ回る。
    public func playNext() async {
        guard let next = nextOrderPosition(wrapping: repeatMode != .off) else { return }
        await play(orderPosition: next)
    }

    /// 前の動画へ手動で戻る。リピート時は先頭から末尾へ回る。
    public func playPrevious() async {
        guard let orderPosition, !order.isEmpty else { return }
        let previous: Int
        if orderPosition - 1 >= 0 {
            previous = orderPosition - 1
        } else if repeatMode != .off {
            previous = order.count - 1
        } else {
            return
        }
        await play(orderPosition: previous)
    }

    /// 再生順序モード（連続 / シャッフル）を設定する。
    ///
    /// 現在再生中の動画は維持したまま、以降の順序を再構築する。
    public func setPlaybackOrder(_ newOrder: PlaybackOrder) {
        guard newOrder != playbackOrder else { return }
        playbackOrder = newOrder
        let position = rebuildOrder(startingFrom: currentIndex)
        if currentIndex != nil {
            orderPosition = position
        }
    }

    /// 連続 ↔ シャッフルをトグルする。
    public func toggleShuffle() {
        setPlaybackOrder(playbackOrder == .shuffle ? .sequential : .shuffle)
    }

    /// リピートモードを設定する。
    public func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
    }

    /// リピートモードを循環的に切り替える（off → all → one → off）。
    public func cycleRepeatMode() {
        repeatMode = repeatMode.next
    }

    // MARK: - Private

    /// 1 動画の再生終了で呼ばれる。リピート / 順序に応じて次へ遷移し、末尾なら停止する。
    private func handleDidPlayToEnd() async {
        // 1 曲リピートは同じ動画を再生し直す。
        if repeatMode == .one, let orderPosition {
            await play(orderPosition: orderPosition)
            return
        }
        // 全体リピートは末尾の次で先頭へ回る。リピートなしは末尾で停止する。
        if let next = nextOrderPosition(wrapping: repeatMode == .all) {
            await play(orderPosition: next)
        } else {
            playerProxy.pause()
        }
    }

    /// 次に再生すべき `order` 上の位置を返す。
    ///
    /// - Parameter wrapping: 末尾を越えたとき先頭（0）へ巻き戻す場合は true。
    private func nextOrderPosition(wrapping: Bool) -> Int? {
        guard let orderPosition, !order.isEmpty else { return nil }
        let next = orderPosition + 1
        if next < order.count {
            return next
        }
        return wrapping ? 0 : nil
    }

    /// 再生順序（`order`）を現在のモードに合わせて再構築する。
    ///
    /// - sequential: プレイリストの並び順そのもの。指定インデックスは `order` 上の同位置になる。
    /// - shuffle: ランダムに並べ替え、指定インデックスを先頭へ据えて再生位置の連続性を保つ。
    ///
    /// - Parameter playlistIndex: 現在再生中の `playlist` 上のインデックス。
    /// - Returns: 再構築後に再生位置として据えるべき `order` 上の位置（要素が無ければ 0）。
    @discardableResult
    private func rebuildOrder(startingFrom playlistIndex: Int?) -> Int {
        let indices = Array(playlist.indices)
        switch playbackOrder {
        case .sequential:
            order = indices
            guard let playlistIndex, let position = order.firstIndex(of: playlistIndex) else {
                return 0
            }
            return position
        case .shuffle:
            var shuffled = indices.shuffled()
            guard let playlistIndex, shuffled.contains(playlistIndex) else {
                order = shuffled
                return 0
            }
            // 現在の動画を先頭に据える（以降の順序はランダムのまま）。
            shuffled.removeAll { $0 == playlistIndex }
            shuffled.insert(playlistIndex, at: 0)
            order = shuffled
            return 0
        }
    }

    private func registerDidPlayToEndIfNeeded() {
        guard !hasObservedDidPlayToEnd else { return }
        hasObservedDidPlayToEnd = true
        playerProxy.observeDidPlayToEnd { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleDidPlayToEnd()
            }
        }
    }

    private func play(orderPosition position: Int) async {
        guard order.indices.contains(position) else { return }
        let playlistIndex = order[position]
        guard playlist.indices.contains(playlistIndex) else { return }
        orderPosition = position
        _ = await playerProxy.loadAndPlay(playlist[playlistIndex].id)
    }
}
