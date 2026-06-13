//
//  VideoPlayerViewState.swift
//  Library
//
//  再生画面の表示状態。
//

/// 再生画面の表示状態。
///
/// 再生エンジン（AVPlayer）は Features 層では扱わず、描画面のバインドは `VideoPlayerProxy` 経由で
/// 行う（docs-internal/architecture.md の Proxy 境界 / Store 方針を参照）。この状態は読み込みの進行のみを表す。
enum VideoPlayerViewState {

    /// 再生リソースの取得中（取得前の初期状態を含む）。
    case loading

    /// 再生可能。
    case ready

    /// アセットが見つからない等で再生できない。
    case failed
}
