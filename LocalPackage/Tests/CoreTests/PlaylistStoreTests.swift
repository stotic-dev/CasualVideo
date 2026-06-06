//
//  PlaylistStoreTests.swift
//  CoreTests
//
//  PlaylistStore（プレイリスト連続再生 F-4）のロジックを検証する。
//
//  PlaylistStore は再生エンジンの操作を VideoPlayerProxy（クロージャ保持の struct）へ委譲する。
//  テストでは本番の `.live` ではなくクロージャを差し替えた Proxy を注入し（docs/testing.md）、
//  「現在位置の遷移」「再生完了での自動遷移」「境界での停止」などのドメインロジックを検証する。
//

import Testing

@testable import Core

@MainActor
struct PlaylistStoreTests {

    // MARK: - Fixtures

    private func makeAsset(id: String) -> VideoAsset {
        VideoAsset(id: id, duration: 1, creationDate: nil, isInCloud: false)
    }

    private var assets: [VideoAsset] {
        [makeAsset(id: "a"), makeAsset(id: "b"), makeAsset(id: "c")]
    }

    /// loadAndPlay された id を記録するだけの Proxy を作る。
    private func recordingProxy(
        played: Box<[String]>,
        paused: Box<Bool> = Box(false),
        handler: Box<(@MainActor @Sendable () -> Void)?> = Box(nil)
    ) -> VideoPlayerProxy {
        VideoPlayerProxy(
            loadAndPlay: { id in
                await MainActor.run { played.value.append(id) }
                return true
            },
            pause: { paused.value = true },
            observeDidPlayToEnd: { handler.value = $0 }
        )
    }

    // MARK: - 初期状態

    @Test("start 前は currentIndex / currentAsset が nil")
    func initialState_isEmpty() {
        let store = PlaylistStore(playerProxy: VideoPlayerProxy())

        #expect(store.currentIndex == nil)
        #expect(store.currentAsset == nil)
        #expect(store.canPlayNext == false)
        #expect(store.canPlayPrevious == false)
    }

    // MARK: - start()

    @Test("start は指定インデックスの動画を読み込んで再生を開始する")
    func start_playsFromGivenIndex() async {
        let played = Box<[String]>([])
        let store = PlaylistStore(playerProxy: recordingProxy(played: played))

        await store.start(playlist: assets, from: 1)

        #expect(store.currentIndex == 1)
        #expect(store.currentAsset?.id == "b")
        #expect(store.currentPosition == 2)
        #expect(store.totalCount == 3)
        #expect(played.value == ["b"])
    }

    @Test("start は範囲外インデックスを先頭へ丸める")
    func start_clampsOutOfRangeIndex() async {
        let played = Box<[String]>([])
        let store = PlaylistStore(playerProxy: recordingProxy(played: played))

        await store.start(playlist: assets, from: 99)

        #expect(store.currentIndex == 0)
        #expect(played.value == ["a"])
    }

    @Test("空のプレイリストでは start しても再生しない")
    func start_withEmptyPlaylist_doesNothing() async {
        let played = Box<[String]>([])
        let store = PlaylistStore(playerProxy: recordingProxy(played: played))

        await store.start(playlist: [], from: 0)

        #expect(store.currentIndex == nil)
        #expect(played.value.isEmpty)
    }

    @Test("canPlayNext / canPlayPrevious は現在位置に応じて切り替わる")
    func canPlayNextPrevious_dependOnPosition() async {
        let store = PlaylistStore(playerProxy: recordingProxy(played: Box([])))

        await store.start(playlist: assets, from: 0)
        #expect(store.canPlayPrevious == false)
        #expect(store.canPlayNext == true)

        await store.playNext()
        await store.playNext()
        #expect(store.canPlayPrevious == true)
        #expect(store.canPlayNext == false)
    }

    // MARK: - playNext / playPrevious

    @Test("playNext は次の動画へ進めて再生する")
    func playNext_advancesAndPlays() async {
        let played = Box<[String]>([])
        let store = PlaylistStore(playerProxy: recordingProxy(played: played))

        await store.start(playlist: assets, from: 0)
        await store.playNext()

        #expect(store.currentIndex == 1)
        #expect(played.value == ["a", "b"])
    }

    @Test("末尾で playNext しても位置は変わらず再生もしない")
    func playNext_atLast_doesNothing() async {
        let played = Box<[String]>([])
        let store = PlaylistStore(playerProxy: recordingProxy(played: played))

        await store.start(playlist: assets, from: 2)
        await store.playNext()

        #expect(store.currentIndex == 2)
        #expect(played.value == ["c"])
    }

    @Test("playPrevious は前の動画へ戻して再生する")
    func playPrevious_goesBackAndPlays() async {
        let played = Box<[String]>([])
        let store = PlaylistStore(playerProxy: recordingProxy(played: played))

        await store.start(playlist: assets, from: 2)
        await store.playPrevious()

        #expect(store.currentIndex == 1)
        #expect(played.value == ["c", "b"])
    }

    @Test("先頭で playPrevious しても位置は変わらず再生もしない")
    func playPrevious_atFirst_doesNothing() async {
        let played = Box<[String]>([])
        let store = PlaylistStore(playerProxy: recordingProxy(played: played))

        await store.start(playlist: assets, from: 0)
        await store.playPrevious()

        #expect(store.currentIndex == 0)
        #expect(played.value == ["a"])
    }

    // MARK: - 再生完了での自動遷移（F-4 中核）

    @Test("再生完了の通知で次の動画へ自動遷移する")
    func didPlayToEnd_advancesToNext() async {
        let played = Box<[String]>([])
        let handler = Box<(@MainActor @Sendable () -> Void)?>(nil)
        let store = PlaylistStore(playerProxy: recordingProxy(played: played, handler: handler))

        await store.start(playlist: assets, from: 0)
        #expect(store.currentIndex == 0)
        #expect(played.value == ["a"])

        // 1 本目の再生完了を発火 → 2 本目へ自動遷移。
        handler.value?()
        await waitUntil { played.value.count >= 2 }

        #expect(store.currentIndex == 1)
        #expect(played.value == ["a", "b"])
    }

    @Test("末尾の再生完了では次が無いため停止し、自動遷移しない")
    func didPlayToEnd_atLast_pausesWithoutAdvancing() async {
        let played = Box<[String]>([])
        let paused = Box(false)
        let handler = Box<(@MainActor @Sendable () -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played, paused: paused, handler: handler)
        )

        await store.start(playlist: assets, from: 2)
        #expect(played.value == ["c"])

        // 末尾アイテムの再生完了を発火しても進まず、停止する。
        handler.value?()
        await waitUntil { paused.value }

        #expect(store.currentIndex == 2)
        #expect(played.value == ["c"])
        #expect(paused.value)
    }

    // MARK: - シャッフル（F-5）

    @Test("シャッフルに切り替えても現在再生中の動画は維持される")
    func setPlaybackOrder_shuffle_keepsCurrentAsset() async {
        let played = Box<[String]>([])
        let store = PlaylistStore(playerProxy: recordingProxy(played: played))

        await store.start(playlist: assets, from: 1)
        #expect(store.currentAsset?.id == "b")

        store.setPlaybackOrder(.shuffle)

        // 現在の動画は維持され、再生位置は先頭（1 始まりの 1）に据えられる。
        #expect(store.playbackOrder == .shuffle)
        #expect(store.currentAsset?.id == "b")
        #expect(store.currentPosition == 1)
        #expect(store.totalCount == 3)
        // 順序を組み替えただけなので追加再生は発生しない。
        #expect(played.value == ["b"])
    }

    @Test("start 時のシャッフルでも開始インデックスの動画が先頭に来る")
    func start_shuffle_putsStartAssetFirst() async {
        // 何度試行しても開始動画が必ず先頭に維持されることを確認する。
        for _ in 0 ..< 20 {
            let played = Box<[String]>([])
            let store = PlaylistStore(
                playerProxy: recordingProxy(played: played),
                playbackOrder: .shuffle
            )

            await store.start(playlist: assets, from: 2)

            #expect(store.currentAsset?.id == "c")
            #expect(store.currentPosition == 1)
            #expect(played.value == ["c"])
        }
    }

    @Test("シャッフル後も全要素を一巡すると全動画を再生する")
    func shuffle_coversAllAssetsOnce() async {
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            playbackOrder: .shuffle
        )

        await store.start(playlist: assets, from: 0)
        await store.playNext()
        await store.playNext()

        // 開始動画("a")が先頭で、残り 2 本も重複なく再生される。
        #expect(played.value.first == "a")
        #expect(Set(played.value) == Set(["a", "b", "c"]))
        #expect(played.value.count == 3)
    }

    @Test("toggleShuffle は連続 ↔ シャッフルを切り替え、現在位置を維持する")
    func toggleShuffle_switchesOrderKeepingPosition() async {
        let store = PlaylistStore(playerProxy: recordingProxy(played: Box([])))

        await store.start(playlist: assets, from: 1)
        #expect(store.playbackOrder == .sequential)

        store.toggleShuffle()
        #expect(store.playbackOrder == .shuffle)
        #expect(store.currentAsset?.id == "b")

        store.toggleShuffle()
        #expect(store.playbackOrder == .sequential)
        #expect(store.currentAsset?.id == "b")
        // 連続へ戻すと元の並びの位置（2 番目）へ復帰する。
        #expect(store.currentPosition == 2)
    }

    // MARK: - リピート（F-5）

    @Test("リピート all では末尾の再生完了で先頭へ循環する")
    func didPlayToEnd_repeatAll_wrapsToFirst() async {
        let played = Box<[String]>([])
        let handler = Box<(@MainActor @Sendable () -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played, handler: handler),
            repeatMode: .all
        )

        await store.start(playlist: assets, from: 2)
        #expect(played.value == ["c"])

        // 末尾の再生完了 → 先頭へ循環する。
        handler.value?()
        await waitUntil { played.value.count >= 2 }

        #expect(store.currentIndex == 0)
        #expect(played.value == ["c", "a"])
    }

    @Test("リピート one では再生完了で同一動画を再生し直す")
    func didPlayToEnd_repeatOne_replaysSameAsset() async {
        let played = Box<[String]>([])
        let handler = Box<(@MainActor @Sendable () -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played, handler: handler),
            repeatMode: .one
        )

        await store.start(playlist: assets, from: 1)
        #expect(played.value == ["b"])

        handler.value?()
        await waitUntil { played.value.count >= 2 }

        // 同じ動画("b")を再生し直し、位置も変わらない。
        #expect(store.currentIndex == 1)
        #expect(played.value == ["b", "b"])
    }

    @Test("リピート off では末尾の再生完了で停止し循環しない")
    func didPlayToEnd_repeatOff_pausesAtLast() async {
        let played = Box<[String]>([])
        let paused = Box(false)
        let handler = Box<(@MainActor @Sendable () -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played, paused: paused, handler: handler),
            repeatMode: .off
        )

        await store.start(playlist: assets, from: 2)
        #expect(played.value == ["c"])

        handler.value?()
        await waitUntil { paused.value }

        #expect(store.currentIndex == 2)
        #expect(played.value == ["c"])
        #expect(paused.value)
    }

    @Test("リピート時は末尾でも canPlayNext、先頭でも canPlayPrevious が true")
    func canPlayNextPrevious_repeat_allowsWrapping() async {
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: Box([])),
            repeatMode: .all
        )

        // 末尾でも次へ進める（先頭へ循環するため）。
        await store.start(playlist: assets, from: 2)
        #expect(store.canPlayNext == true)
        #expect(store.canPlayPrevious == true)

        // 先頭でも前へ戻れる（末尾へ循環するため）。
        await store.start(playlist: assets, from: 0)
        #expect(store.canPlayNext == true)
        #expect(store.canPlayPrevious == true)
    }

    @Test("リピート時の playNext は末尾から先頭へラップする")
    func playNext_repeat_wrapsToFirst() async {
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            repeatMode: .all
        )

        await store.start(playlist: assets, from: 2)
        await store.playNext()

        #expect(store.currentIndex == 0)
        #expect(played.value == ["c", "a"])
    }

    @Test("リピート時の playPrevious は先頭から末尾へラップする")
    func playPrevious_repeat_wrapsToLast() async {
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            repeatMode: .all
        )

        await store.start(playlist: assets, from: 0)
        await store.playPrevious()

        #expect(store.currentIndex == 2)
        #expect(played.value == ["a", "c"])
    }

    // MARK: - Test utility

    /// 条件が満たされるまで MainActor を譲りながら待つ（自動遷移は Task で非同期に進むため）。
    private func waitUntil(
        _ condition: () -> Bool,
        maxYields: Int = 1000
    ) async {
        var count = 0
        while !condition() && count < maxYields {
            await Task.yield()
            count += 1
        }
    }
}

/// クロージャ内から書き換え可能な参照ボックス。@MainActor 上のテストでのみ使用する。
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
