//
//  VideoPlayerViewState.swift
//  Library
//
//  再生画面の表示状態。
//

import AVKit

/// 再生画面の表示状態。
///
/// 再生リソース（AVPlayer）は View ライフサイクルに紐づくため、Store ではなく View 層の状態として保持する
/// （docs/architecture.md の Store 方針 / docs/swiftui.md の遅延読み込み例外を参照）。
enum VideoPlayerViewState {

    /// 再生リソースの取得中（取得前の初期状態を含む）。
    case loading

    /// 再生可能。`AVPlayer` を保持する。
    case ready(AVPlayer)

    /// アセットが見つからない等で再生できない。
    case failed
}
