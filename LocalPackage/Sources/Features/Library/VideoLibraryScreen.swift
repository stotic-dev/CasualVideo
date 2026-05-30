//
//  VideoLibraryScreen.swift
//  Library
//
//  写真ライブラリの動画一覧画面（F-1）。
//

import Core
import SwiftUI

/// 写真ライブラリの動画一覧画面。Feature の公開エントリ。
public struct VideoLibraryScreen: View {

    @Environment(\.videoLibraryRepository) private var repository

    public init() {}

    /// App から構築する際のファクトリ。
    public static func make() -> some View {
        VideoLibraryScreen()
    }

    public var body: some View {
        // Repository を環境から受け取り Store を生成する。
        VideoLibraryContentView(store: VideoLibraryStore(repository: repository))
    }
}

private struct VideoLibraryContentView: View {

    @State private var store: VideoLibraryStore

    init(store: VideoLibraryStore) {
        self._store = State(initialValue: store)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("動画")
        }
        .task {
            await store.onAppear()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let videos):
            if videos.isEmpty {
                ContentUnavailableView(
                    "動画がありません",
                    systemImage: "video.slash",
                    description: Text("写真ライブラリに動画が見つかりませんでした。")
                )
            } else {
                VideoGridView(videos: videos, store: store)
            }

        case .unauthorized(let status):
            VideoLibraryUnauthorizedView(status: status) {
                Task { await store.reload() }
            }
        }
    }
}

private struct VideoGridView: View {

    let videos: [VideoAsset]
    let store: VideoLibraryStore

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(videos) { video in
                    VideoCellView(video: video, store: store)
                        .aspectRatio(1, contentMode: .fill)
                }
            }
            .padding(2)
        }
    }
}
