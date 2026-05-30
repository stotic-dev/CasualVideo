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
                    VideoCellView(video: video)
                        .aspectRatio(1, contentMode: .fill)
                }
            }
            .padding(2)
        }
    }
}
