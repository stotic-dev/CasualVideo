//
//  VideoLibraryScreen.swift
//  Library
//
//  写真ライブラリの動画一覧画面（F-1）。
//
//  Screen と presentational View の分離方針は docs/swiftui.md を参照。
//  - Screen（VideoLibraryScreen）: Environment から Store を取得し副作用を担う。
//  - View（VideoLibraryView）: init で受け取った状態を表示するだけ。副作用を持たない。
//

import Core
import SwiftUI

/// 写真ライブラリの動画一覧画面。Feature の公開エントリ。
public struct VideoLibraryScreen: View {

    @Environment(VideoLibraryStore.self) var store

    /// App から構築する際のファクトリ。
    public static func make() -> some View {
        VideoLibraryScreen()
    }

    public var body: some View {
        // Store のロード状態を UI の表示状態へ変換し、presentational View へ渡す。
        VideoLibraryView(state: VideoLibraryViewState(loadState: store.loadState)) {
            await store.reload()
        }
        .task {
            // ライフサイクルに紐づく副作用は Screen 側に置く。
            await store.load()
        }
    }
}

/// 動画一覧の presentational View。init で受け取った状態を表示するだけで副作用を持たない。
///
/// Store や Repository に依存しないため、Preview / Snapshot テストで状態を直接注入して
/// 各ケースを再現できる（docs/swiftui.md 参照）。
struct VideoLibraryView: View {

    let state: VideoLibraryViewState
    /// 未許可状態からの再試行アクション。副作用の実体は Screen 側にある。
    let onRetry: () async -> Void

    /// モーダルで再生中の動画。nil の間は再生画面を提示しない。
    @State private var selectedVideo: VideoAsset?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("動画")
        }
        // 一覧セルから選んだ動画（F-2 再生画面）をモーダル（fullScreenCover）で提示する。
        .fullScreenCover(item: $selectedVideo) { asset in
            VideoPlayerScreen(asset: asset) {
                // 閉じる導線。選択状態をクリアしてモーダルを閉じる。
                selectedVideo = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            ContentUnavailableView(
                "動画がありません",
                systemImage: "video.slash",
                description: Text("写真ライブラリに動画が見つかりませんでした。")
            )

        case .videos(let videos):
            VideoGridView(videos: videos) { video in
                selectedVideo = video
            }

        case .unauthorized(let status):
            VideoLibraryUnauthorizedView(status: status) {
                Task { await onRetry() }
            }
        }
    }
}
