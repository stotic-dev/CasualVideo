//
//  VideoCellView.swift
//  Library
//
//  動画一覧のセル。サムネイル + 再生時間 + 撮影日 + iCloud インジケータを表示する。
//

import Core
import SwiftUI

struct VideoCellView: View {

    let video: VideoAsset

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // サムネイル表示（取得・Preview モック分岐）は共通コンポーネントに委譲する。
            ThumbnailView(assetID: video.id)
            gradientOverlay
            metaOverlay
            if video.isInCloud {
                iCloudIndicator
            }
        }
        .clipShape(.rect(cornerRadius: 4))
    }

    private var gradientOverlay: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.55)],
            startPoint: .center,
            endPoint: .bottom
        )
    }

    private var metaOverlay: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let date = video.creationDate {
                Text(date, format: .dateTime.year().month().day())
                    .font(.system(size: 10))
            }
            Text(Self.durationText(video.duration))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .shadow(radius: 1)
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var iCloudIndicator: some View {
        Image(systemName: "icloud.and.arrow.down")
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .shadow(radius: 1)
            .padding(4)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
