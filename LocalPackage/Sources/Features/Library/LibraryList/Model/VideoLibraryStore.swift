//
//  VideoLibraryStore.swift
//  Library
//
//  写真ライブラリ動画一覧画面の状態を管理する Store。
//

import Core
import Foundation
import Observation

/// 動画一覧のロード状態。
///
/// UI の表示状態（ViewState）ではなく、ドメインデータの読み込み進行を表す。
/// UI 制御に必要な表示状態への変換は View 層が担う。
public enum VideoLibraryLoadState: Sendable, Equatable {

    /// 初期状態（許可確認前）。
    case idle

    /// 読み込み中。
    case loading

    /// 動画一覧の読み込み完了。
    case loaded([VideoAsset])

    /// アクセス未許可・拒否などで読み込めない。
    case unauthorized(VideoLibraryAuthorizationStatus)
}

/// 写真ライブラリの動画一覧を管理する Store。
///
/// 状態はカプセル化し、公開 API（メソッド・computed property）を通じてのみ更新・参照する。
/// UI 関連型は扱わず、ドメインのロード状態のみを公開する（docs-internal/architecture.md 参照）。
@MainActor
@Observable
public final class VideoLibraryStore {

    /// 現在のロード状態。
    public private(set) var loadState: VideoLibraryLoadState = .idle

    private let repository: VideoLibraryRepository

    public init(repository: VideoLibraryRepository) {
        self.repository = repository
    }

    /// 許可状態を確認し、必要なら許可リクエストを行ってから一覧を読み込む。
    public func load() async {
        // 既に読み込み済みなら再取得しない（再表示時のちらつき防止）。
        if case .loaded = loadState { return }

        let current = await repository.authorizationStatus()
        let status: VideoLibraryAuthorizationStatus
        if current == .notDetermined {
            status = await repository.requestAuthorization()
        } else {
            status = current
        }

        guard status.canAccessLibrary else {
            loadState = .unauthorized(status)
            return
        }

        await loadVideos()
    }

    /// 一覧を再読み込みする。
    public func reload() async {
        let status = await repository.authorizationStatus()
        guard status.canAccessLibrary else {
            loadState = .unauthorized(status)
            return
        }
        await loadVideos()
    }

    private func loadVideos() async {
        loadState = .loading
        let videos = await repository.fetchVideos()
        loadState = .loaded(videos)
    }
}
