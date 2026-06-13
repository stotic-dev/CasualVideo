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
    /// セルタップ時のアクション。選択された動画を呼び出し元（VideoLibraryView）へ渡す。
    let onSelect: (VideoAsset) -> Void

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(videos) { video in
                    // セルタップで再生画面（F-2）をモーダル表示する。
                    // 選択状態の保持・モーダル提示は VideoLibraryView 側で行う。
                    Button {
                        onSelect(video)
                    } label: {
                        VideoCellView(video: video)
                            .aspectRatio(1, contentMode: .fill)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
        }
    }
}
