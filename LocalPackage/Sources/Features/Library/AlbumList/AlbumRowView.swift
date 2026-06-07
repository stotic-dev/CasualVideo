//
//  AlbumRowView.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/07.
//

import SwiftUI
import Core

/// アルバム一覧の 1 行分の表示。
struct AlbumRowView: View {

    let album: VideoAlbum

    var body: some View {
        HStack(spacing: 12) {
            // 代表サムネイル（取得・Preview モック分岐は共通コンポーネントに委譲）。
            ThumbnailView(assetID: album.thumbnailAssetID)
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title.isEmpty ? "（無題）" : album.title)
                Text("\(album.videoCount) 本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("AlbumRowView") {
    List {
        AlbumRowView(
            album: VideoAlbum(id: "1", title: "旅行", videoCount: 12, thumbnailAssetID: "travel")
        )
        AlbumRowView(
            album: VideoAlbum(id: "2", title: "", videoCount: 1, thumbnailAssetID: nil)
        )
    }
    .environment(\.isPreview, true)
}
