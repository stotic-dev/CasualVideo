//
//  AlbumListScreen.swift
//  Library
//
//  アルバム一覧画面（F-6 アルバム単位再生の起点）。
//
//  Screen と presentational View の分離方針は docs/swiftui.md を参照。
//  - Screen（AlbumListScreen）: Repository から Store を生成し副作用を担う。
//  - View（AlbumListView）: 受け取った状態を表示するだけ。副作用を持たない。
//
//  アルバムは「動的＝再生開始時に最新のアルバム内容を取得」する。アルバムタップ時には
//  動画一覧を保持せず、再生開始時に VideoPlayerScreen が Repository 経由で取得する。
//

import Core
import SwiftUI

/// アルバム一覧画面。
struct AlbumListScreen: View {

    @Environment(\.videoLibraryRepository) private var repository
    /// アプリスコープの再生 Store。アルバム単位の再生開始はここへ委譲する。
    @Environment(PlaybackStore.self) private var playbackStore
    @State private var store: AlbumListStore?

    var body: some View {
        AlbumListView(
            state: store.map { AlbumListViewState(loadState: $0.loadState) } ?? .loading,
            // アルバム単位の連続再生（F-6）。再生開始時に最新のアルバム内容を動的取得する。
            onPlay: { album in
                playbackStore.start { await repository.fetchVideosInAlbum(album.id) }
            }
        )
        .task {
            // Repository は Environment 経由で取得し、Feature 内 Store を生成する。
            let store = store ?? AlbumListStore(repository: repository)
            self.store = store
            await store.load()
        }
    }
}

/// アルバム一覧の presentational View。init で受け取った状態を表示するだけで副作用を持たない。
struct AlbumListView: View {

    let state: AlbumListViewState
    /// アルバムの再生開始（F-6）。再生・提示の実体は呼び出し元（再生セッション）へ委譲する。
    let onPlay: (VideoAlbum) -> Void

    var body: some View {
        content
            .navigationTitle("アルバム")
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            ContentUnavailableView(
                "アルバムがありません",
                systemImage: "rectangle.stack.badge.play",
                description: Text("動画を含むアルバムが見つかりませんでした。")
            )

        case .albums(let albums):
            List(albums) { album in
                Button {
                    onPlay(album)
                } label: {
                    AlbumRowView(album: album)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#if DEBUG
#Preview("アルバムあり") {
    NavigationStack {
        AlbumListView(
            state: .albums([
                VideoAlbum(id: "1", title: "旅行", videoCount: 12, thumbnailAssetID: "travel"),
                VideoAlbum(id: "2", title: "家族", videoCount: 5, thumbnailAssetID: "family"),
                VideoAlbum(id: "3", title: "お気に入り", videoCount: 28, thumbnailAssetID: "favorites"),
                VideoAlbum(id: "4", title: "", videoCount: 1, thumbnailAssetID: nil)
            ]),
            onPlay: { _ in }
        )
    }
    .environment(\.isPreview, true)
}

#Preview("空") {
    NavigationStack {
        AlbumListView(state: .empty, onPlay: { _ in })
    }
    .environment(\.isPreview, true)
}

#Preview("読み込み中") {
    NavigationStack {
        AlbumListView(state: .loading, onPlay: { _ in })
    }
    .environment(\.isPreview, true)
}
#endif
