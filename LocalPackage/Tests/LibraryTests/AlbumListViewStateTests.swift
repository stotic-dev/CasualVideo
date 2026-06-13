//
//  AlbumListViewStateTests.swift
//  LibraryTests
//
//  AlbumListViewState のロード状態 → 表示状態への変換ロジックを検証する。
//

import Core
import Testing

@testable import Library

private func makeAlbum(id: String) -> VideoAlbum {
    VideoAlbum(id: id, title: id, videoCount: 1, thumbnailAssetID: id)
}

@Test("idle は loading 表示になる")
func viewState_fromIdle_isLoading() {
    #expect(AlbumListViewState(loadState: .idle) == .loading)
}

@Test("loading は loading 表示になる")
func viewState_fromLoading_isLoading() {
    #expect(AlbumListViewState(loadState: .loading) == .loading)
}

@Test("loaded が空のときは empty 表示になる")
func viewState_fromLoadedEmpty_isEmpty() {
    #expect(AlbumListViewState(loadState: .loaded([])) == .empty)
}

@Test("loaded にアルバムがあるときは albums 表示になる")
func viewState_fromLoadedWithAlbums_isAlbums() {
    let albums = [makeAlbum(id: "a"), makeAlbum(id: "b")]
    #expect(AlbumListViewState(loadState: .loaded(albums)) == .albums(albums))
}
