//
//  PlaylistStore.swift
//  Core
//
//  プレイリスト連続再生（F-4）のドメイン状態と再生制御を担う Store。
//

import Foundation
import Observation

/// プレイリストの連続再生を管理する Store。
///
/// 「再生対象の動画一覧」と「現在の再生位置」を保持し、`VideoPlayerProxy` を介して再生する。
/// 1 動画の再生終了で次の動画へ自動遷移する（F-4 / requirements 3.3）。
///
/// - Note: 特定画面に依存しないドメイン状態のみを持つ（UI 型は扱わない）。再生操作は抽象（`VideoPlayerProxy`）へ委譲する。
@Observable
@MainActor
public final class PlaylistStore {

    /// 連続再生対象の動画一覧。
    public private(set) var playlist: [VideoAsset] = []

    /// 現在再生中の動画のインデックス。未再生時は `nil`。
    public private(set) var currentIndex: Int?

    private let playerProxy: VideoPlayerProxy

    /// 再生完了オブザーバを一度だけ登録したかどうか。
    private var hasObservedDidPlayToEnd = false

    public init(playerProxy: VideoPlayerProxy) {
        self.playerProxy = playerProxy
    }

    /// 現在再生中の動画。
    public var currentAsset: VideoAsset? {
        guard let currentIndex, playlist.indices.contains(currentIndex) else { return nil }
        return playlist[currentIndex]
    }

    /// 現在の再生位置（1 始まり）。未再生時は `nil`。
    public var currentPosition: Int? {
        currentIndex.map { $0 + 1 }
    }

    /// プレイリスト内の総数。
    public var totalCount: Int {
        playlist.count
    }

    /// 次の動画へ進めるか。
    public var canPlayNext: Bool {
        guard let currentIndex else { return false }
        return currentIndex + 1 < playlist.count
    }

    /// 前の動画へ戻れるか。
    public var canPlayPrevious: Bool {
        guard let currentIndex else { return false }
        return currentIndex - 1 >= 0
    }

    /// 指定したプレイリストを、指定インデックスから連続再生する。
    ///
    /// - Parameters:
    ///   - assets: 再生対象の動画一覧。
    ///   - startIndex: 再生を開始するインデックス（既定は先頭）。
    public func start(playlist assets: [VideoAsset], from startIndex: Int = 0) async {
        guard !assets.isEmpty else { return }
        playlist = assets
        registerDidPlayToEndIfNeeded()
        let index = assets.indices.contains(startIndex) ? startIndex : 0
        await play(at: index)
    }

    /// 次の動画へ手動で進める。
    public func playNext() async {
        guard let currentIndex else { return }
        await play(at: currentIndex + 1)
    }

    /// 前の動画へ手動で戻る。
    public func playPrevious() async {
        guard let currentIndex else { return }
        await play(at: currentIndex - 1)
    }

    // MARK: - Private

    /// 1 動画の再生終了で呼ばれる。次があれば自動遷移し、最後なら停止する。
    private func handleDidPlayToEnd() async {
        guard let currentIndex else { return }
        let nextIndex = currentIndex + 1
        if playlist.indices.contains(nextIndex) {
            await play(at: nextIndex)
        } else {
            // プレイリスト末尾の動画が終了したら停止する。
            playerProxy.pause()
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

    private func play(at index: Int) async {
        guard playlist.indices.contains(index) else { return }
        currentIndex = index
        _ = await playerProxy.loadAndPlay(playlist[index].id)
    }
}
