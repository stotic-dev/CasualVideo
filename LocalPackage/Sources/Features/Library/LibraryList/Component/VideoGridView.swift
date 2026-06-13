//
//  VideoGridView.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/05/30.
//

import SwiftUI
import Core

struct VideoGridView: View {

    let videos: [VideoAsset]

    /// 選択モード中かどうか。true の間はタップが再生遷移ではなく選択トグルになる（F-6 手動選択）。
    let isSelecting: Bool

    /// 選択中の動画 ID 集合。
    let selectedIDs: Set<VideoAsset.ID>

    /// 選択モード時のセルタップ。選択トグルを行う。
    let onToggleSelection: (VideoAsset) -> Void

    /// 通常時のセルタップ。再生画面（F-2）のモーダル提示を呼び出し元へ委譲する。
    let onSelect: (VideoAsset) -> Void

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(videos) { video in
                    cell(for: video)
                }
            }
            .padding(2)
        }
    }

    @ViewBuilder
    private func cell(for video: VideoAsset) -> some View {
        if isSelecting {
            // 選択モード中はタップで選択状態をトグルする。再生遷移は行わない。
            Button {
                onToggleSelection(video)
            } label: {
                VideoCellView(video: video)
                    .aspectRatio(1, contentMode: .fill)
                    .overlay(alignment: .topTrailing) {
                        selectionBadge(isSelected: selectedIDs.contains(video.id))
                    }
            }
            .buttonStyle(.plain)
        } else {
            // 通常時はセルタップで再生画面（F-2）をモーダル提示する。提示の実体は
            // VideoLibraryView の fullScreenCover で行い、ここでは選択を通知するだけ。
            Button {
                onSelect(video)
            } label: {
                VideoCellView(video: video)
                    .aspectRatio(1, contentMode: .fill)
            }
            .buttonStyle(.plain)
        }
    }

    private func selectionBadge(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20))
            .foregroundStyle(isSelected ? Color.accentColor : .white)
            .background(isSelected ? Color.white : .clear, in: .circle)
            .shadow(radius: 1)
            .padding(6)
    }
}
