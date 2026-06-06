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

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(videos) { video in
                    // セルタップで再生画面（F-2）へ遷移する。遷移先は VideoLibraryView の
                    // navigationDestination(for: VideoAsset.self) で解決する。
                    NavigationLink(value: video) {
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
