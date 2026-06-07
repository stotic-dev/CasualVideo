//
//  VideoLibraryViewState.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/05/30.
//

import Core

/// 動画一覧画面の表示状態。
///
/// Store のロード状態（`VideoLibraryLoadState`）を UI 制御に必要な単位へ変換したもの。
/// 表示分岐に対応する形（読み込み中／空／一覧／未許可）で持つ。
enum VideoLibraryViewState: Equatable {

    /// 読み込み中（許可確認前の初期状態を含む）。
    case loading

    /// 動画が 1 件も無い。
    case empty

    /// 表示する動画一覧。
    case videos([VideoAsset])

    /// アクセス未許可・拒否などで一覧を表示できない。
    case unauthorized(VideoLibraryAuthorizationStatus)

    init(loadState: VideoLibraryLoadState) {
        switch loadState {
        case .idle, .loading:
            self = .loading
        case .loaded(let videos):
            self = videos.isEmpty ? .empty : .videos(videos)
        case .unauthorized(let status):
            self = .unauthorized(status)
        }
    }
}
