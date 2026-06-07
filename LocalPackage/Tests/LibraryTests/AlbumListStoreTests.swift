//
//  AlbumListStoreTests.swift
//  LibraryTests
//
//  AlbumListStore のロード状態遷移ロジックを検証する。
//

import Core
import Testing

@testable import Library

// MARK: - Helpers

private func makeAlbum(id: String) -> VideoAlbum {
    VideoAlbum(id: id, title: id, videoCount: 1, thumbnailAssetID: id)
}

// MARK: - load()

@MainActor
@Test("初期状態は idle")
func albumListStore_initialState_isIdle() {
    // Arrange
    let store = AlbumListStore(repository: VideoLibraryRepository(fetchAlbums: { [] }))

    // Assert
    #expect(store.loadState == .idle)
}

@MainActor
@Test("load でアルバムを取得して loaded になる")
func albumListLoad_fetchesAlbums_setsLoaded() async {
    // Arrange
    let albums = [makeAlbum(id: "a"), makeAlbum(id: "b")]
    let store = AlbumListStore(repository: VideoLibraryRepository(fetchAlbums: { albums }))

    // Act
    await store.load()

    // Assert
    #expect(store.loadState == .loaded(albums))
}

@MainActor
@Test("取得結果が空でも loaded（空配列）になる")
func albumListLoad_whenEmpty_setsLoadedWithEmpty() async {
    // Arrange
    let store = AlbumListStore(repository: VideoLibraryRepository(fetchAlbums: { [] }))

    // Act
    await store.load()

    // Assert
    #expect(store.loadState == .loaded([]))
}

@MainActor
@Test("既に loaded のときは再取得せず状態を維持する")
func albumListLoad_whenAlreadyLoaded_doesNotRefetch() async {
    // Arrange
    let firstAlbums = [makeAlbum(id: "first")]
    let callCount = Mutable(0)
    let albums = Mutable(firstAlbums)
    let store = AlbumListStore(
        repository: VideoLibraryRepository(
            fetchAlbums: {
                callCount.value += 1
                return albums.value
            }
        )
    )

    // Act（1 回目で loaded にした後、取得結果を変えて再度 load）
    await store.load()
    albums.value = [makeAlbum(id: "second")]
    await store.load()

    // Assert（1 回目の結果を維持し、取得は 1 回のみ）
    #expect(store.loadState == .loaded(firstAlbums))
    #expect(callCount.value == 1)
}

// MARK: - Test utility

/// クロージャ内から書き換え可能な参照ボックス。
/// @MainActor 上のテストでのみ使用するため Sendable 制約は付けない。
private final class Mutable<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
