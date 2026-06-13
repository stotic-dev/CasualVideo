//
//  PlaylistRequest.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/07.
//

import Foundation
import Core

/// 全動画再生 / 手動選択再生の遷移トリガ。確定済みプレイリストを保持する。
struct PlaylistRequest: Identifiable, Hashable {
    let id = UUID()
    let videos: [VideoAsset]
}
