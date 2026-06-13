//
//  AlbumListLoadState.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/07.
//

import Core

/// アルバム一覧のロード状態。
enum AlbumListLoadState: Sendable, Equatable {

    /// 初期状態（読み込み前）。
    case idle

    /// 読み込み中。
    case loading

    /// アルバム一覧の読み込み完了。
    case loaded([VideoAlbum])
}