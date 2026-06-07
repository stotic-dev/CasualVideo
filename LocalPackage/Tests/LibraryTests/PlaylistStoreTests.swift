//
//  PlaylistStoreTests.swift
//  LibraryTests
//
//  PlaylistStore（プレイリスト連続再生 F-4）のロジックを検証する。
//
//  PlaylistStore は再生エンジンの操作を VideoPlayerProxy（クロージャ保持の struct）へ委譲する。
//  テストでは本番の `.live` ではなくクロージャを差し替えた Proxy を注入し（docs-internal/testing.md）、
//  「現在位置の遷移」「再生完了での自動遷移」「境界での停止」などのドメインロジックを検証する。
//
//  プレゼンテーションロジックのテストは複雑になりがちなため、各ケースは AAA パターン
//  （Arrange / Act / Assert）をコメントで明示する。状態検証は公開状態をまとめて検証する
//  共通 Assertion（`assertState`）で行い、副作用に関連する Proxy（Mock）の検証はケースごとに別途行う。
//

import Core
import Foundation
import Testing

@testable import Library

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
        playResumed: Box<Bool> = Box(false),
        seeked: Box<[TimeInterval]> = Box([]),
        progressHandler: Box<(@MainActor @Sendable (PlaybackProgress) -> Void)?> = Box(nil),
        handler: Box<(@MainActor @Sendable () -> Void)?> = Box(nil)
    ) -> VideoPlayerProxy {
        VideoPlayerProxy(
            loadAndPlay: { id in
                await MainActor.run { played.value.append(id) }
                return true
            },
            play: { playResumed.value = true },
            pause: { paused.value = true },
            observeDidPlayToEnd: { handler.value = $0 },
            seek: { seeked.value.append($0) },
            observeProgress: { progressHandler.value = $0 }
        )
    }

    /// updateNowPlayingInfo の引数と observeRemoteCommand のハンドラを記録する Proxy を作る。
    private func recordingNowPlayingProxy(
        infos: Box<[NowPlayingInfo]>,
        remoteHandler: Box<(@MainActor @Sendable (RemoteCommand) -> Void)?> = Box(nil),
        observeCount: Box<Int> = Box(0)
    ) -> NowPlayingInfoProxy {
        NowPlayingInfoProxy(
            updateNowPlayingInfo: { infos.value.append($0) },
            observeRemoteCommand: { handler in
                observeCount.value += 1
                remoteHandler.value = handler
            }
        )
    }

    // MARK: - 初期状態

    @Test("start 前は currentIndex / currentAsset が nil")
    func initialState_isEmpty() {
        // Arrange
        let store = PlaylistStore(
            playerProxy: VideoPlayerProxy(),
            nowPlayingInfoProxy: NowPlayingInfoProxy()
        )

        // Act
        // （操作なし。生成直後の初期状態を検証する。）

        // Assert
        assertState(store, ExpectedState())
    }

    // MARK: - start()

    @Test("start は指定インデックスの動画を読み込んで再生を開始する")
    func start_playsFromGivenIndex() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy()
        )

        // Act
        await store.start(playlist: assets, from: 1)

        // Assert
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            isPlaying: true,
            currentIndex: 1,
            currentAssetID: "b",
            currentPosition: 2,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: true
        ))
        #expect(played.value == ["b"])
    }

    @Test("start は範囲外インデックスを先頭へ丸める")
    func start_clampsOutOfRangeIndex() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy()
        )

        // Act
        await store.start(playlist: assets, from: 99)

        // Assert
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            isPlaying: true,
            currentIndex: 0,
            currentAssetID: "a",
            currentPosition: 1,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: false
        ))
        #expect(played.value == ["a"])
    }

    @Test("空のプレイリストでは start しても再生しない")
    func start_withEmptyPlaylist_doesNothing() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy()
        )

        // Act
        await store.start(playlist: [], from: 0)

        // Assert
        assertState(store, ExpectedState())
        #expect(played.value.isEmpty)
    }

    @Test("canPlayNext / canPlayPrevious は現在位置に応じて切り替わる")
    func canPlayNextPrevious_dependOnPosition() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy()
        )

        // Act: 先頭から再生開始
        await store.start(playlist: assets, from: 0)

        // Assert: 先頭では前へ戻れず、次へは進める
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            isPlaying: true,
            currentIndex: 0,
            currentAssetID: "a",
            currentPosition: 1,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: false
        ))

        // Act: 末尾まで進める
        await store.playNext()
        await store.playNext()

        // Assert: 末尾では次へ進めず、前へは戻れる
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            isPlaying: true,
            currentIndex: 2,
            currentAssetID: "c",
            currentPosition: 3,
            totalCount: 3,
            canPlayNext: false,
            canPlayPrevious: true
        ))
        #expect(played.value == ["a", "b", "c"])
    }

    // MARK: - playNext / playPrevious

    @Test("playNext は次の動画へ進めて再生する")
    func playNext_advancesAndPlays() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy()
        )
        await store.start(playlist: assets, from: 0)

        // Act
        await store.playNext()

        // Assert
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            isPlaying: true,
            currentIndex: 1,
            currentAssetID: "b",
            currentPosition: 2,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: true
        ))
        #expect(played.value == ["a", "b"])
    }

    @Test("末尾で playNext しても位置は変わらず再生もしない")
    func playNext_atLast_doesNothing() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy()
        )
        await store.start(playlist: assets, from: 2)

        // Act
        await store.playNext()

        // Assert
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            isPlaying: true,
            currentIndex: 2,
            currentAssetID: "c",
            currentPosition: 3,
            totalCount: 3,
            canPlayNext: false,
            canPlayPrevious: true
        ))
        #expect(played.value == ["c"])
    }

    @Test("playPrevious は前の動画へ戻して再生する")
    func playPrevious_goesBackAndPlays() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy()
        )
        await store.start(playlist: assets, from: 2)

        // Act
        await store.playPrevious()

        // Assert
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            isPlaying: true,
            currentIndex: 1,
            currentAssetID: "b",
            currentPosition: 2,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: true
        ))
        #expect(played.value == ["c", "b"])
    }

    @Test("先頭で playPrevious しても位置は変わらず再生もしない")
    func playPrevious_atFirst_doesNothing() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy()
        )
        await store.start(playlist: assets, from: 0)

        // Act
        await store.playPrevious()

        // Assert
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            isPlaying: true,
            currentIndex: 0,
            currentAssetID: "a",
            currentPosition: 1,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: false
        ))
        #expect(played.value == ["a"])
    }

    // MARK: - 再生完了での自動遷移（F-4 中核）

    @Test("再生完了の通知で次の動画へ自動遷移する")
    func didPlayToEnd_advancesToNext() async {
        // Arrange
        let played = Box<[String]>([])
        let handler = Box<(@MainActor @Sendable () -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played, handler: handler),
            nowPlayingInfoProxy: NowPlayingInfoProxy()
        )
        await store.start(playlist: assets, from: 0)
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            isPlaying: true,
            currentIndex: 0,
            currentAssetID: "a",
            currentPosition: 1,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: false
        ))
        #expect(played.value == ["a"])

        // Act: 1 本目の再生完了を発火 → 2 本目へ自動遷移
        handler.value?()
        await waitUntil { played.value.count >= 2 && !store.isPreparingItem }

        // Assert
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            isPlaying: true,
            currentIndex: 1,
            currentAssetID: "b",
            currentPosition: 2,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: true
        ))
        #expect(played.value == ["a", "b"])
    }

    @Test("末尾の再生完了では次が無いため停止し、自動遷移しない")
    func didPlayToEnd_atLast_pausesWithoutAdvancing() async {
        // Arrange
        let played = Box<[String]>([])
        let paused = Box(false)
        let handler = Box<(@MainActor @Sendable () -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played, paused: paused, handler: handler),
            nowPlayingInfoProxy: NowPlayingInfoProxy()
        )
        await store.start(playlist: assets, from: 2)
        #expect(played.value == ["c"])

        // Act: 末尾アイテムの再生完了を発火しても進まず、停止する
        handler.value?()
        await waitUntil { paused.value }

        // Assert
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            isPlaying: false,
            currentIndex: 2,
            currentAssetID: "c",
            currentPosition: 3,
            totalCount: 3,
            canPlayNext: false,
            canPlayPrevious: true
        ))
        #expect(played.value == ["c"])
        #expect(paused.value)
    }

    // MARK: - シャッフル（F-5）

    @Test("シャッフルに切り替えても現在再生中の動画は維持される")
    func setPlaybackOrder_shuffle_keepsCurrentAsset() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy()
        )
        await store.start(playlist: assets, from: 1)
        #expect(store.currentAsset?.id == "b")

        // Act
        store.setPlaybackOrder(.shuffle)

        // Assert: 現在の動画は維持され、再生位置は先頭（1 始まりの 1）に据えられる。
        //         順序を組み替えただけなので追加再生は発生しない。
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            playbackOrder: .shuffle,
            isPlaying: true,
            currentIndex: 1,
            currentAssetID: "b",
            currentPosition: 1,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: false
        ))
        #expect(played.value == ["b"])
    }

    @Test("start 時のシャッフルでも開始インデックスの動画が先頭に来る")
    func start_shuffle_putsStartAssetFirst() async {
        // 何度試行しても開始動画が必ず先頭に維持されることを確認する。
        for _ in 0 ..< 20 {
            // Arrange
            let played = Box<[String]>([])
            let store = PlaylistStore(
                playerProxy: recordingProxy(played: played),
                nowPlayingInfoProxy: NowPlayingInfoProxy(),
                playbackOrder: .shuffle
            )

            // Act
            await store.start(playlist: assets, from: 2)

            // Assert
            assertState(store, ExpectedState(
                playlistIDs: ["a", "b", "c"],
                playbackOrder: .shuffle,
                isPlaying: true,
                currentIndex: 2,
                currentAssetID: "c",
                currentPosition: 1,
                totalCount: 3,
                canPlayNext: true,
                canPlayPrevious: false
            ))
            #expect(played.value == ["c"])
        }
    }

    @Test("シャッフル後も全要素を一巡すると全動画を再生する")
    func shuffle_coversAllAssetsOnce() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy(),
            playbackOrder: .shuffle
        )

        // Act
        await store.start(playlist: assets, from: 0)
        await store.playNext()
        await store.playNext()

        // Assert: 末尾の動画はランダムだが、公開状態は再生結果から決まるため共通 Assertion で検証する。
        let lastID = played.value.last
        let lastIndex = assets.firstIndex { $0.id == lastID }
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            playbackOrder: .shuffle,
            isPlaying: true,
            currentIndex: lastIndex,
            currentAssetID: lastID,
            currentPosition: 3,
            totalCount: 3,
            canPlayNext: false,
            canPlayPrevious: true
        ))
        // 開始動画("a")が先頭で、残り 2 本も重複なく再生される。
        #expect(played.value.first == "a")
        #expect(Set(played.value) == Set(["a", "b", "c"]))
        #expect(played.value.count == 3)
    }

    @Test("toggleShuffle は連続 ↔ シャッフルを切り替え、現在位置を維持する")
    func toggleShuffle_switchesOrderKeepingPosition() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy()
        )
        await store.start(playlist: assets, from: 1)
        #expect(store.playbackOrder == .sequential)

        // Act: 連続 → シャッフル
        store.toggleShuffle()

        // Assert: シャッフル後も現在の動画は維持され、位置は先頭になる
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            playbackOrder: .shuffle,
            isPlaying: true,
            currentIndex: 1,
            currentAssetID: "b",
            currentPosition: 1,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: false
        ))

        // Act: シャッフル → 連続
        store.toggleShuffle()

        // Assert: 連続へ戻すと元の並びの位置（2 番目）へ復帰する
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            playbackOrder: .sequential,
            isPlaying: true,
            currentIndex: 1,
            currentAssetID: "b",
            currentPosition: 2,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: true
        ))
        #expect(played.value == ["b"])
    }

    // MARK: - リピート（F-5）

    @Test("リピート all では末尾の再生完了で先頭へ循環する")
    func didPlayToEnd_repeatAll_wrapsToFirst() async {
        // Arrange
        let played = Box<[String]>([])
        let handler = Box<(@MainActor @Sendable () -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played, handler: handler),
            nowPlayingInfoProxy: NowPlayingInfoProxy(),
            repeatMode: .all
        )
        await store.start(playlist: assets, from: 2)
        #expect(played.value == ["c"])

        // Act: 末尾の再生完了 → 先頭へ循環する
        handler.value?()
        await waitUntil { played.value.count >= 2 && !store.isPreparingItem }

        // Assert
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            repeatMode: .all,
            isPlaying: true,
            currentIndex: 0,
            currentAssetID: "a",
            currentPosition: 1,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: true
        ))
        #expect(played.value == ["c", "a"])
    }

    @Test("リピート one では再生完了で同一動画を再生し直す")
    func didPlayToEnd_repeatOne_replaysSameAsset() async {
        // Arrange
        let played = Box<[String]>([])
        let handler = Box<(@MainActor @Sendable () -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played, handler: handler),
            nowPlayingInfoProxy: NowPlayingInfoProxy(),
            repeatMode: .one
        )
        await store.start(playlist: assets, from: 1)
        #expect(played.value == ["b"])

        // Act
        handler.value?()
        await waitUntil { played.value.count >= 2 && !store.isPreparingItem }

        // Assert: 同じ動画("b")を再生し直し、位置も変わらない
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            repeatMode: .one,
            isPlaying: true,
            currentIndex: 1,
            currentAssetID: "b",
            currentPosition: 2,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: true
        ))
        #expect(played.value == ["b", "b"])
    }

    @Test("リピート off では末尾の再生完了で停止し循環しない")
    func didPlayToEnd_repeatOff_pausesAtLast() async {
        // Arrange
        let played = Box<[String]>([])
        let paused = Box(false)
        let handler = Box<(@MainActor @Sendable () -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played, paused: paused, handler: handler),
            nowPlayingInfoProxy: NowPlayingInfoProxy(),
            repeatMode: .off
        )
        await store.start(playlist: assets, from: 2)
        #expect(played.value == ["c"])

        // Act
        handler.value?()
        await waitUntil { paused.value }

        // Assert
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            repeatMode: .off,
            isPlaying: false,
            currentIndex: 2,
            currentAssetID: "c",
            currentPosition: 3,
            totalCount: 3,
            canPlayNext: false,
            canPlayPrevious: true
        ))
        #expect(played.value == ["c"])
        #expect(paused.value)
    }

    @Test("リピート時は末尾でも canPlayNext、先頭でも canPlayPrevious が true")
    func canPlayNextPrevious_repeat_allowsWrapping() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy(),
            repeatMode: .all
        )

        // Act: 末尾から再生開始
        await store.start(playlist: assets, from: 2)

        // Assert: 末尾でも次へ進める（先頭へ循環するため）
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            repeatMode: .all,
            isPlaying: true,
            currentIndex: 2,
            currentAssetID: "c",
            currentPosition: 3,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: true
        ))

        // Act: 先頭から再生開始
        await store.start(playlist: assets, from: 0)

        // Assert: 先頭でも前へ戻れる（末尾へ循環するため）
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            repeatMode: .all,
            isPlaying: true,
            currentIndex: 0,
            currentAssetID: "a",
            currentPosition: 1,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: true
        ))
    }

    @Test("リピート時の playNext は末尾から先頭へラップする")
    func playNext_repeat_wrapsToFirst() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy(),
            repeatMode: .all
        )
        await store.start(playlist: assets, from: 2)

        // Act
        await store.playNext()

        // Assert
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            repeatMode: .all,
            isPlaying: true,
            currentIndex: 0,
            currentAssetID: "a",
            currentPosition: 1,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: true
        ))
        #expect(played.value == ["c", "a"])
    }

    @Test("リピート時の playPrevious は先頭から末尾へラップする")
    func playPrevious_repeat_wrapsToLast() async {
        // Arrange
        let played = Box<[String]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: NowPlayingInfoProxy(),
            repeatMode: .all
        )
        await store.start(playlist: assets, from: 0)

        // Act
        await store.playPrevious()

        // Assert
        assertState(store, ExpectedState(
            playlistIDs: ["a", "b", "c"],
            repeatMode: .all,
            isPlaying: true,
            currentIndex: 2,
            currentAssetID: "c",
            currentPosition: 3,
            totalCount: 3,
            canPlayNext: true,
            canPlayPrevious: true
        ))
        #expect(played.value == ["a", "c"])
    }

    // MARK: - NowPlayingInfo の更新（F-5）

    @Test("start（再生開始）で現在アセットの NowPlayingInfo が更新される")
    func start_updatesNowPlayingInfo() async {
        // Arrange
        let played = Box<[String]>([])
        let infos = Box<[NowPlayingInfo]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: recordingNowPlayingProxy(infos: infos)
        )

        // Act
        await store.start(playlist: assets, from: 1)

        // Assert: 直近の更新は再生中の現在アセット("b")を反映する
        let last = infos.value.last
        #expect(last?.assetID == "b")
        #expect(last?.isPlaying == true)
        #expect(last?.title == "CasualVideo")
    }

    @Test("togglePlayPause で再生状態を反映した NowPlayingInfo が更新される")
    func togglePlayPause_updatesNowPlayingInfo() async {
        // Arrange
        let played = Box<[String]>([])
        let infos = Box<[NowPlayingInfo]>([])
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: recordingNowPlayingProxy(infos: infos)
        )
        await store.start(playlist: assets, from: 0)

        // Act: 一時停止 → 再開
        store.togglePlayPause()

        // Assert: 一時停止が NowPlayingInfo に反映される
        #expect(store.isPlaying == false)
        #expect(infos.value.last?.isPlaying == false)

        // Act
        store.togglePlayPause()

        // Assert: 再開が NowPlayingInfo に反映される
        #expect(store.isPlaying == true)
        #expect(infos.value.last?.isPlaying == true)
    }

    @Test("seek で再生位置（elapsedTime）を反映した NowPlayingInfo が更新される")
    func seek_updatesNowPlayingInfo() async {
        // Arrange
        let played = Box<[String]>([])
        let infos = Box<[NowPlayingInfo]>([])
        let progressHandler = Box<(@MainActor @Sendable (PlaybackProgress) -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played, progressHandler: progressHandler),
            nowPlayingInfoProxy: recordingNowPlayingProxy(infos: infos)
        )
        await store.start(playlist: assets, from: 0)
        // シーク可能にするため進捗（再生長さ）を流し込む
        progressHandler.value?(PlaybackProgress(currentTime: 0, duration: 10))

        // Act
        store.seek(to: 4)

        // Assert: 即時反映された再生位置が NowPlayingInfo にも載る
        #expect(store.progress.currentTime == 4)
        #expect(infos.value.last?.elapsedTime == 4)
    }

    @Test("進捗監視の更新で NowPlayingInfo が更新される")
    func observeProgress_updatesNowPlayingInfo() async {
        // Arrange
        let played = Box<[String]>([])
        let infos = Box<[NowPlayingInfo]>([])
        let progressHandler = Box<(@MainActor @Sendable (PlaybackProgress) -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played, progressHandler: progressHandler),
            nowPlayingInfoProxy: recordingNowPlayingProxy(infos: infos)
        )
        await store.start(playlist: assets, from: 0)

        // Act: 進捗を流す
        progressHandler.value?(PlaybackProgress(currentTime: 3, duration: 10))

        // Assert: 進捗が NowPlayingInfo に反映される
        #expect(infos.value.last?.elapsedTime == 3)
        #expect(infos.value.last?.duration == 10)
    }

    // MARK: - RemoteCommand のディスパッチ（F-5）

    @Test("start 時に observeRemoteCommand は一度だけ登録される")
    func start_registersRemoteCommandObserverOnce() async {
        // Arrange
        let played = Box<[String]>([])
        let observeCount = Box(0)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: recordingNowPlayingProxy(infos: Box([]), observeCount: observeCount)
        )

        // Act: 複数回 start しても登録は一度きり
        await store.start(playlist: assets, from: 0)
        await store.start(playlist: assets, from: 1)

        // Assert
        #expect(observeCount.value == 1)
    }

    @Test("RemoteCommand .toggle で再生状態がトグルされる")
    func remoteCommand_toggle_togglesPlayback() async {
        // Arrange
        let played = Box<[String]>([])
        let remoteHandler = Box<(@MainActor @Sendable (RemoteCommand) -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: recordingNowPlayingProxy(infos: Box([]), remoteHandler: remoteHandler)
        )
        await store.start(playlist: assets, from: 0)
        #expect(store.isPlaying == true)

        // Act & Assert: toggle で一時停止
        remoteHandler.value?(.toggle)
        #expect(store.isPlaying == false)

        // Act & Assert: 再度 toggle で再開
        remoteHandler.value?(.toggle)
        #expect(store.isPlaying == true)
    }

    @Test("RemoteCommand .pause / .play は現在状態に応じてディスパッチされる")
    func remoteCommand_playPause_dispatch() async {
        // Arrange
        let played = Box<[String]>([])
        let remoteHandler = Box<(@MainActor @Sendable (RemoteCommand) -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: recordingNowPlayingProxy(infos: Box([]), remoteHandler: remoteHandler)
        )
        await store.start(playlist: assets, from: 0)

        // Act & Assert: .pause で一時停止
        remoteHandler.value?(.pause)
        #expect(store.isPlaying == false)

        // Act & Assert: すでに停止中の .pause は無視される
        remoteHandler.value?(.pause)
        #expect(store.isPlaying == false)

        // Act & Assert: .play で再開
        remoteHandler.value?(.play)
        #expect(store.isPlaying == true)

        // Act & Assert: すでに再生中の .play は無視される
        remoteHandler.value?(.play)
        #expect(store.isPlaying == true)
    }

    @Test("RemoteCommand .next / .previous で前後の動画へ遷移する")
    func remoteCommand_nextPrevious_dispatch() async {
        // Arrange
        let played = Box<[String]>([])
        let remoteHandler = Box<(@MainActor @Sendable (RemoteCommand) -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played),
            nowPlayingInfoProxy: recordingNowPlayingProxy(infos: Box([]), remoteHandler: remoteHandler)
        )
        await store.start(playlist: assets, from: 0)

        // Act: .next で次の動画へ（ディスパッチは Task のため完了を待つ）
        remoteHandler.value?(.next)
        await waitUntil { store.currentIndex == 1 && !store.isPreparingItem }

        // Assert
        #expect(store.currentAsset?.id == "b")
        #expect(played.value == ["a", "b"])

        // Act: .previous で前の動画へ
        remoteHandler.value?(.previous)
        await waitUntil { store.currentIndex == 0 && !store.isPreparingItem }

        // Assert
        #expect(store.currentAsset?.id == "a")
        #expect(played.value == ["a", "b", "a"])
    }

    @Test("RemoteCommand .seek で指定秒へシークする")
    func remoteCommand_seek_dispatch() async {
        // Arrange
        let played = Box<[String]>([])
        let seeked = Box<[TimeInterval]>([])
        let progressHandler = Box<(@MainActor @Sendable (PlaybackProgress) -> Void)?>(nil)
        let remoteHandler = Box<(@MainActor @Sendable (RemoteCommand) -> Void)?>(nil)
        let store = PlaylistStore(
            playerProxy: recordingProxy(played: played, seeked: seeked, progressHandler: progressHandler),
            nowPlayingInfoProxy: recordingNowPlayingProxy(infos: Box([]), remoteHandler: remoteHandler)
        )
        await store.start(playlist: assets, from: 0)
        progressHandler.value?(PlaybackProgress(currentTime: 0, duration: 10))

        // Act
        remoteHandler.value?(.seek(5))

        // Assert: Proxy へシークが委譲され、進捗にも即時反映される
        #expect(seeked.value == [5])
        #expect(store.progress.currentTime == 5)
    }

    // MARK: - 共通 Assertion

    /// PlaylistStore の公開状態すべての期待値。
    ///
    /// 既定値は「未再生（start 前）」の初期状態に一致させてある。各テストは差分だけ上書きして渡す。
    private struct ExpectedState {
        var playlistIDs: [String] = []
        var playbackOrder: PlaybackOrder = .sequential
        var repeatMode: RepeatMode = .off
        var isPlaying: Bool = false
        var isPreparingItem: Bool = false
        var currentIndex: Int?
        var currentAssetID: String?
        var currentPosition: Int?
        var totalCount: Int = 0
        var canPlayNext: Bool = false
        var canPlayPrevious: Bool = false
        var progress: PlaybackProgress = PlaybackProgress()
    }

    /// 公開状態を一括検証する共通 Assertion。
    ///
    /// あるケースで副作用として変化する状態だけでなく **公開状態すべて** を毎回検証することで、
    /// 実装変更による意図しない状態変化（想定外のプロパティが書き換わる等）を検知する。
    /// Proxy（Mock）の検証は副作用に応じて各ケースで別途行う。
    private func assertState(
        _ store: PlaylistStore,
        _ expected: ExpectedState,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(store.playlist.map(\.id) == expected.playlistIDs, sourceLocation: sourceLocation)
        #expect(store.playbackOrder == expected.playbackOrder, sourceLocation: sourceLocation)
        #expect(store.repeatMode == expected.repeatMode, sourceLocation: sourceLocation)
        #expect(store.isPlaying == expected.isPlaying, sourceLocation: sourceLocation)
        #expect(store.isPreparingItem == expected.isPreparingItem, sourceLocation: sourceLocation)
        #expect(store.currentIndex == expected.currentIndex, sourceLocation: sourceLocation)
        #expect(store.currentAsset?.id == expected.currentAssetID, sourceLocation: sourceLocation)
        #expect(store.currentPosition == expected.currentPosition, sourceLocation: sourceLocation)
        #expect(store.totalCount == expected.totalCount, sourceLocation: sourceLocation)
        #expect(store.canPlayNext == expected.canPlayNext, sourceLocation: sourceLocation)
        #expect(store.canPlayPrevious == expected.canPlayPrevious, sourceLocation: sourceLocation)
        #expect(store.progress == expected.progress, sourceLocation: sourceLocation)
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
