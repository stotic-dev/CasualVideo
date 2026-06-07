//
//  PlaylistStore.swift
//  Library
//
//  プレイリスト連続再生（F-4）＋ シャッフル / リピート（F-5）のドメイン状態と再生制御を担う Store。
//

import Foundation
import Observation
import Core

/// プレイリストの連続再生・シャッフル・リピートを管理する Store。
///
/// 「再生対象の動画一覧」「再生順序」「現在の再生位置」を保持し、`VideoPlayerProxy` を介して再生する。
/// 1 動画の再生終了で次の動画へ自動遷移する（F-4 / requirements 3.3）。
/// 再生順序（連続 / シャッフル）とリピート（off / all / one）を切り替えられる（F-5 / requirements 3.2）。
///
/// - Note: 特定画面に依存しないドメイン状態のみを持つ（UI 型は扱わない）。再生操作は抽象（`VideoPlayerProxy`）へ委譲する。
@Observable
@MainActor
final class PlaylistStore {

    /// 連続再生対象の動画一覧（プレイリストの並び順そのもの）。
    private(set) var playlist: [VideoAsset] = []

    /// 再生順序モード（連続 / シャッフル）。
    private(set) var playbackOrder: PlaybackOrder

    /// リピートモード（off / all / one）。
    private(set) var repeatMode: RepeatMode

    /// 現在再生中かどうか（再生 = true / 一時停止 = false）。
    ///
    /// 再生/一時停止ボタンの表示状態に用いる。再生エンジンへの操作は `VideoPlayerProxy` 経由で行う。
    private(set) var isPlaying = false

    /// 再生アイテム（PlayerItem）をセットアップ中かどうか。
    ///
    /// `loadAndPlay`（読み込み完了まで await）が進行している間 true。
    /// この間は再生コントロールを非活性化しインジケーターを表示する（UI 側の判断材料）。
    private(set) var isPreparingItem = false

    /// 現在再生中アイテムの再生進捗（シークバー表示 / F-6 に用いる）。
    ///
    /// 再生エンジンの定期時刻監視（`VideoPlayerProxy.observeProgress`）を購読して更新する。
    private(set) var progress = PlaybackProgress()

    /// 音声ミュート中かどうか（F-7）。再生開始時はデフォルト設定で初期化される。
    private(set) var isMuted: Bool

    /// 現在の再生速度（F-7）。再生開始時はデフォルト設定で初期化される。
    private(set) var playbackRate: PlaybackRate
    
    /// エラーが発生した時に設定される
    private(set) var error: ErrorAlertItem?

    private let playerProxy: VideoPlayerProxy
    private let nowPlayingInfoProxy: NowPlayingInfoProxy

    /// `playlist` のインデックスを再生する順に並べた配列。シャッフル時はここが入れ替わる。
    private var order: [Int] = []

    /// `order` 内での現在位置。未再生時は `nil`。
    private var orderPosition: Int?

    /// 再生完了オブザーバを一度だけ登録したかどうか。
    private var hasObservedDidPlayToEnd = false

    /// 再生進捗オブザーバを一度だけ登録したかどうか。
    private var hasObservedProgress = false

    /// リモートコマンドオブザーバを一度だけ登録したかどうか。
    private var hasObservedRemoteCommand = false

    init(
        playerProxy: VideoPlayerProxy,
        nowPlayingInfoProxy: NowPlayingInfoProxy,
        playbackOrder: PlaybackOrder = .sequential,
        repeatMode: RepeatMode = .off,
        isMuted: Bool = false,
        playbackRate: PlaybackRate = .normal
    ) {
        self.playerProxy = playerProxy
        self.nowPlayingInfoProxy = nowPlayingInfoProxy
        self.playbackOrder = playbackOrder
        self.repeatMode = repeatMode
        self.isMuted = isMuted
        self.playbackRate = playbackRate
    }

    /// 現在再生中の動画のインデックス（`playlist` 上の位置）。未再生時は `nil`。
    var currentIndex: Int? {
        guard let orderPosition, order.indices.contains(orderPosition) else { return nil }
        return order[orderPosition]
    }

    /// 現在再生中の動画。
    var currentAsset: VideoAsset? {
        // エラーがある場合は現在再生できていないということになるので、nilを返す
        if error != nil { return nil }
        guard let currentIndex, playlist.indices.contains(currentIndex) else { return nil }
        return playlist[currentIndex]
    }

    /// 現在の再生位置（再生順での 1 始まり）。未再生時は `nil`。
    var currentPosition: Int? {
        orderPosition.map { $0 + 1 }
    }

    /// プレイリスト内の総数。
    var totalCount: Int {
        playlist.count
    }

    /// 次の動画へ進めるか。リピート時（all / one）は要素があれば常に進める（末尾でも先頭へ戻る）。
    var canPlayNext: Bool {
        guard let orderPosition else { return false }
        if repeatMode != .off { return !order.isEmpty }
        return orderPosition + 1 < order.count
    }

    /// 前の動画へ戻れるか。リピート時（all / one）は要素があれば常に戻れる（先頭でも末尾へ回る）。
    var canPlayPrevious: Bool {
        guard let orderPosition else { return false }
        if repeatMode != .off { return !order.isEmpty }
        return orderPosition - 1 >= 0
    }

    /// 指定したプレイリストを、指定インデックスから再生する。
    ///
    /// - Parameters:
    ///   - assets: 再生対象の動画一覧。
    ///   - startIndex: 再生を開始する `playlist` 上のインデックス（既定は先頭）。
    func start(playlist assets: [VideoAsset], from startIndex: Int = 0) async {
        guard !assets.isEmpty else { return }
        playlist = assets
        registerDidPlayToEndIfNeeded()
        registerProgressObserverIfNeeded()
        registerRemoteCommandObserverIfNeeded()
        // 再生開始前にデフォルト（ミュート・速度 / F-7）を再生エンジンへ適用する。
        // player レベルで保持されるため、以降の item 差し替え後も有効。
        playerProxy.setMuted(isMuted)
        playerProxy.setRate(Float(playbackRate.rawValue))
        let index = assets.indices.contains(startIndex) ? startIndex : 0
        let position = rebuildOrder(startingFrom: index)
        await play(orderPosition: position)
    }

    /// 次の動画へ手動で進める。リピート時は末尾から先頭へ回る。
    func playNext() async {
        guard let next = nextOrderPosition(wrapping: repeatMode != .off) else { return }
        await play(orderPosition: next)
    }

    /// 前の動画へ手動で戻る。リピート時は先頭から末尾へ回る。
    func playPrevious() async {
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
    func setPlaybackOrder(_ newOrder: PlaybackOrder) {
        guard newOrder != playbackOrder else { return }
        playbackOrder = newOrder
        let position = rebuildOrder(startingFrom: currentIndex)
        if currentIndex != nil {
            orderPosition = position
        }
    }

    /// 連続 ↔ シャッフルをトグルする。
    func toggleShuffle() {
        setPlaybackOrder(playbackOrder == .shuffle ? .sequential : .shuffle)
    }

    /// リピートモードを設定する。
    func setRepeatMode(_ mode: RepeatMode) {
        repeatMode = mode
    }

    /// リピートモードを循環的に切り替える（off → all → one → off）。
    func cycleRepeatMode() {
        repeatMode = repeatMode.next
    }

    /// 再生 / 一時停止をトグルする。
    ///
    /// セットアップ中（`isPreparingItem`）は操作を受け付けない。再生エンジンの操作は Proxy へ委譲する。
    func togglePlayPause() {
        guard !isPreparingItem else { return }
        if isPlaying {
            playerProxy.pause()
            isPlaying = false
        } else {
            playerProxy.play()
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    /// 指定秒へシークする（シークバー操作 / F-6）。
    ///
    /// セットアップ中（`isPreparingItem`）は受け付けない。シーク可能な長さが無い場合も無視する。
    /// 表示の追従性のため、進捗監視の更新を待たずに `progress.currentTime` を即時反映する。
    func seek(to seconds: TimeInterval) {
        guard !isPreparingItem, progress.isSeekable else { return }
        let clamped = min(max(seconds, 0), progress.duration)
        playerProxy.seek(clamped)
        progress.currentTime = clamped
        updateNowPlayingInfo()
    }

    /// 音声ミュートをトグルする（F-7）。再生エンジンの操作は Proxy へ委譲する。
    func toggleMute() {
        isMuted.toggle()
        playerProxy.setMuted(isMuted)
    }

    /// 再生速度を設定する（F-7）。再生エンジンの操作は Proxy へ委譲する。
    func setPlaybackRate(_ rate: PlaybackRate) {
        playbackRate = rate
        playerProxy.setRate(Float(rate.rawValue))
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
            isPlaying = false
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

    private func registerProgressObserverIfNeeded() {
        guard !hasObservedProgress else { return }
        hasObservedProgress = true
        playerProxy.observeProgress { [weak self] progress in
            guard let self else { return }
            self.progress = progress
            self.updateNowPlayingInfo()
        }
    }

    private func registerRemoteCommandObserverIfNeeded() {
        guard !hasObservedRemoteCommand else { return }
        hasObservedRemoteCommand = true
        nowPlayingInfoProxy.observeRemoteCommand { [weak self] command in
            self?.handleRemoteCommand(command)
        }
    }

    /// リモートコマンド（ロック画面 / コントロールセンター等）を既存の再生操作へディスパッチする。
    private func handleRemoteCommand(_ command: RemoteCommand) {
        switch command {
        case .play:
            guard !isPlaying else { return }
            togglePlayPause()
        case .pause:
            guard isPlaying else { return }
            togglePlayPause()
        case .toggle:
            togglePlayPause()
        case .next:
            Task { await playNext() }
        case .previous:
            Task { await playPrevious() }
        case .seek(let seconds):
            seek(to: seconds)
        }
    }

    /// 現在の再生状態から `NowPlayingInfo` を構築し、Proxy 経由でシステムへ反映する（F-5）。
    ///
    /// タイトルは "CasualVideo" 固定（`VideoAsset` はファイル名を持たないため）。アートワークは
    /// `assetID` を参照に App 側でサムネイル取得して設定する（Store は UI 型を扱わない）。
    private func updateNowPlayingInfo() {
        let info = NowPlayingInfo(
            title: "CasualVideo",
            duration: progress.duration,
            elapsedTime: progress.currentTime,
            isPlaying: isPlaying,
            rate: playbackRate,
            assetID: currentAsset?.id
        )
        nowPlayingInfoProxy.updateNowPlayingInfo(info)
    }

    private func play(orderPosition position: Int) async {
        guard order.indices.contains(position) else { return }
        let playlistIndex = order[position]
        guard playlist.indices.contains(playlistIndex) else { return }
        orderPosition = position
        // PlayerItem のセットアップ（読み込み完了まで）中はコントロールを非活性化させる。
        isPreparingItem = true
        let didPlay = await playerProxy.loadAndPlay(playlist[playlistIndex].id)
        isPreparingItem = false
        // 読み込みに成功したものは再生開始状態（loadAndPlay は再生まで行う）。
        if didPlay {
            isPlaying = true
        } else {
            // 読み込みに失敗したらエラーに倒す
            error = .init(error: AppDomainError.failedLoadVideo)
        }
        // 新しいアセットの Now Playing 情報（タイトル / アートワーク参照）を反映する（F-5）。
        updateNowPlayingInfo()
    }
}
