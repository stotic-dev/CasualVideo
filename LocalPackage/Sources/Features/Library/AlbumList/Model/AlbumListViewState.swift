//
//  AlbumListViewState.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/07.
//

import Core

/// アルバム一覧の表示状態。
enum AlbumListViewState: Equatable {
    case loading
    case empty
    case albums([VideoAlbum])

    init(loadState: AlbumListLoadState) {
        switch loadState {
        case .idle, .loading:
            self = .loading
        case .loaded(let albums):
            self = albums.isEmpty ? .empty : .albums(albums)
        }
    }
}