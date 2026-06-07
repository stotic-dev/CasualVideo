//
//  ThumbnailView.swift
//  Library
//
//  写真ライブラリのサムネイル画像を表示する共通コンポーネント。
//
//  動画一覧セル（VideoCellView）・アルバム一覧（AlbumListScreen）など、取得済みサムネイルを
//  表示する箇所で共通利用する。取得は `VideoLibraryRepository.loadThumbnail` 経由で行い、
//  読み込み中はプレースホルダを表示する。
//
//  Preview（`\.isPreview` が true）では再生エンジン同様に PhotoKit 取得が行えないため、モックの
//  サムネイルを表示する。本番／Preview の分岐をこのコンポーネント内に閉じることで、利用側（各画面）は
//  Preview 都合を意識せず済み、影響範囲を狭くできる。
//

import Core
import SwiftUI

/// 取得済みサムネイル画像を表示する共通ビュー。
///
/// 表示サイズは利用側が `.frame` / `.aspectRatio` 等で指定する。指定された表示サイズに合わせて
/// ピクセルサイズを算出し、遅延・非同期でサムネイルを取得する。
struct ThumbnailView: View {

    /// 表示対象アセットの識別子。nil の場合はプレースホルダ（モック）を表示する。
    let assetID: VideoAsset.ID?

    @Environment(\.videoLibraryRepository) private var repository
    @Environment(\.displayScale) private var displayScale
    @Environment(\.isPreview) private var isPreview

    @State private var thumbnail: CGImage?

    var body: some View {
        GeometryReader { proxy in
            thumbnailContent
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .task {
                    // 表示時に遅延・非同期でサムネイルを取得する。
                    await loadIfNeeded(displaySize: proxy.size)
                }
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if isPreview {
            // Preview では PhotoKit 取得ができないため、モックのサムネイルを表示する。
            MockThumbnail(assetID: assetID)
        } else if let thumbnail {
            Image(decorative: thumbnail, scale: displayScale)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "video")
                    .foregroundStyle(.secondary)
            }
    }

    private func loadIfNeeded(displaySize: CGSize) async {
        // Preview ではモック表示のため取得しない。取得済み・サイズ未確定・ID 不在なら何もしない。
        guard !isPreview, thumbnail == nil, let assetID else { return }
        guard displaySize.width > 0, displaySize.height > 0 else { return }
        let pixelSize = CGSize(
            width: displaySize.width * displayScale,
            height: displaySize.height * displayScale
        )
        thumbnail = await repository.loadThumbnail(assetID, pixelSize)
    }
}

/// Preview 用のモックサムネイル。
///
/// `assetID` から決定的に色相を選び、一覧での見た目の差（複数サムネイルが並ぶ様子）を再現する。
private struct MockThumbnail: View {

    let assetID: VideoAsset.ID?

    var body: some View {
        LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.45, brightness: 0.85),
                Color(hue: hue, saturation: 0.6, brightness: 0.5)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    /// `assetID` から決定的に算出する色相（0...1）。プロセス間でばらつかないよう独自に和を取る。
    private var hue: Double {
        let id = assetID ?? "mock"
        let sum = id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 360) / 360
    }
}
