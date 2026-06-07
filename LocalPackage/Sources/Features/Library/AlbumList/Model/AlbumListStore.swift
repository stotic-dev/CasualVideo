//
//  AlbumListStore.swift
//  Library
//
//  アルバム一覧画面（F-6 アルバム単位再生の起点）のロード状態を管理する Store。
//

import Core
import Foundation
import Observation

/// アルバム一覧のロード状態。
enum AlbumListLoadState: Sendable, Equatable {

    /// 初期状態（読み込み前）。
    case idle

    /// 読み込み中。
    case loading

    /// アルバム一覧の読み込み完了。
    case loaded([VideoAlbum])
}

/// 写真ライブラリのアルバム一覧を管理する Store。
///
/// 状態はカプセル化し、公開 API を通じてのみ更新・参照する。UI 関連型は扱わない。
/// 単一 Feature（Library）内でのみ使うため Core には上げず Feature 内に閉じる。
@MainActor
@Observable
final class AlbumListStore {

    /// 現在のロード状態。
    private(set) var loadState: AlbumListLoadState = .idle

    private let repository: VideoLibraryRepository

    init(repository: VideoLibraryRepository) {
        self.repository = repository
    }

    /// アルバム一覧を読み込む。
    func load() async {
        if case .loaded = loadState { return }
        loadState = .loading
        let albums = await repository.fetchAlbums()
        loadState = .loaded(albums)
    }
}
