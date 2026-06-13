//
//  AlbumPlayerScreen.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/07.
//

import SwiftUI
import Core

/// アルバム内動画を再生開始時に動的取得して連続再生する画面（F-6）。
///
/// VideoPlayerScreen のプロバイダ型イニシャライザに、アルバム内動画を取得するクロージャを渡す。
/// これにより再生の起点としての配線を Feature 内に閉じつつ既存の再生フローを再利用する。
struct AlbumPlayerScreen: View {

    let album: VideoAlbum

    @Environment(\.videoLibraryRepository) private var repository

    var body: some View {
        VideoPlayerScreen {
            // 再生開始時に最新のアルバム内容を取得する（動的取得）。
            await repository.fetchVideosInAlbum(album.id)
        }
    }
}
