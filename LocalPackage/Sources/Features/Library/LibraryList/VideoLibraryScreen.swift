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

    /// 選択モード中かどうか（F-6 手動選択）。ビュー都合の状態のため presentational 側で保持する。
    @State private var isSelecting = false

    /// 選択中の動画 ID 集合。
    @State private var selectedIDs: Set<VideoAsset.ID> = []

    /// 連続再生プレイリスト（全動画再生 / 手動選択再生）への遷移トリガ。
    @State private var playlistRequest: PlaylistRequest?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("動画")
                .toolbar { toolbarContent }
                .navigationDestination(for: VideoAsset.self) { asset in
                    // 一覧セルからの遷移先（F-2 再生画面）。
                    // F-4: 表示中の一覧全体をプレイリストとし、選択動画から連続再生する。
                    VideoPlayerScreen(
                        playlist: playlist,
                        startIndex: playlist.firstIndex(of: asset) ?? 0
                    )
                }
                .navigationDestination(item: $playlistRequest) { request in
                    // 全動画再生 / 手動選択再生（F-6）。確定済みプレイリストを固定で渡す。
                    VideoPlayerScreen(playlist: request.videos)
                }
                .navigationDestination(for: AlbumListDestination.self) { _ in
                    // アルバム一覧（F-6 アルバム単位再生の起点）。
                    AlbumListScreen()
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if case .videos = state {
            ToolbarItemGroup(placement: .primaryAction) {
                if isSelecting {
                    Button("再生") { startSelectedPlayback() }
                        .disabled(selectedIDs.isEmpty)
                    Button("キャンセル") { exitSelectionMode() }
                } else {
                    // 全動画再生（F-6 全動画=ライブラリ全体の明示的な導線）。
                    Button {
                        playlistRequest = PlaylistRequest(videos: playlist)
                    } label: {
                        Label("全動画を再生", systemImage: "play.rectangle.on.rectangle")
                    }
                    .disabled(playlist.isEmpty)

                    // アルバム一覧（F-6 アルバム単位再生の起点）。
                    NavigationLink(value: AlbumListDestination()) {
                        Label("アルバム", systemImage: "rectangle.stack")
                    }

                    // 手動選択モードへ入る（F-6 手動選択）。
                    Button {
                        isSelecting = true
                    } label: {
                        Label("選択", systemImage: "checkmark.circle")
                    }
                }
            }
        }
    }

    /// 現在表示中の動画一覧（プレイリストの元になる）。一覧表示中以外は空。
    private var playlist: [VideoAsset] {
        if case .videos(let videos) = state { return videos }
        return []
    }

    /// 選択された動画を表示順で抽出して再生へ遷移する。
    private func startSelectedPlayback() {
        let selected = playlist.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        playlistRequest = PlaylistRequest(videos: selected)
        exitSelectionMode()
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func toggleSelection(_ video: VideoAsset) {
        if selectedIDs.contains(video.id) {
            selectedIDs.remove(video.id)
        } else {
            selectedIDs.insert(video.id)
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
            VideoGridView(
                videos: videos,
                isSelecting: isSelecting,
                selectedIDs: selectedIDs,
                onToggleSelection: toggleSelection
            )

        case .unauthorized(let status):
            VideoLibraryUnauthorizedView(status: status) {
                Task { await onRetry() }
            }
        }
    }
}

/// アルバム一覧画面への遷移先を表すマーカー型。
private struct AlbumListDestination: Hashable {}
