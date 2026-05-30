//
//  VideoLibraryStore.swift
//  Library
//
//  写真ライブラリ動画一覧画面の状態を管理する Store。
//

import Core
import CoreGraphics
import Foundation
import Observation

/// 動画一覧画面の表示状態。
public enum VideoLibraryViewState: Sendable, Equatable {

    /// 初期状態（許可確認前）。
    case idle

    /// 読み込み中。
    case loading

    /// 動画一覧の読み込み完了。
    case loaded([VideoAsset])

    /// アクセス未許可・拒否などで一覧を表示できない。
    case unauthorized(VideoLibraryAuthorizationStatus)
}

/// 写真ライブラリ動画一覧画面の Store。
///
/// 状態はカプセル化し、公開 API（メソッド・computed property）を通じてのみ更新・参照する。
@MainActor
@Observable
public final class VideoLibraryStore {

    /// 現在の表示状態。
    public private(set) var state: VideoLibraryViewState = .idle

    private let repository: VideoLibraryRepository

    public init(repository: VideoLibraryRepository) {
        self.repository = repository
    }

    /// 画面表示時に呼び出す。許可状態を確認し、必要なら許可リクエストを行ってから一覧を読み込む。
    public func onAppear() async {
        // 既に読み込み済みなら再取得しない（再表示時のちらつき防止）。
        if case .loaded = state { return }

        let current = await repository.authorizationStatus()
        let status: VideoLibraryAuthorizationStatus
        if current == .notDetermined {
            status = await repository.requestAuthorization()
        } else {
            status = current
        }

        guard status.canAccessLibrary else {
            state = .unauthorized(status)
            return
        }

        await loadVideos()
    }

    /// 一覧を再読み込みする。
    public func reload() async {
        let status = await repository.authorizationStatus()
        guard status.canAccessLibrary else {
            state = .unauthorized(status)
            return
        }
        await loadVideos()
    }

    /// 指定アセットのサムネイルを取得する。View のセル表示時に遅延呼び出しする想定。
    public func thumbnail(for id: VideoAsset.ID, size: CGSize) async -> CGImage? {
        await repository.loadThumbnail(id, size)
    }

    private func loadVideos() async {
        state = .loading
        let videos = await repository.fetchVideos()
        state = .loaded(videos)
    }
}
