//
//  VideoPlayerViewState.swift
//  Library
//
//  再生画面の表示状態を表すドメインモデル。
//

/// 再生画面の表示状態。
///
/// 再生セッションの進行（`PlaybackStore.Phase`）と Chromecast へのキャスト有無（`isCasting`）という
/// 複数の状態を、画面が分岐すべき単一の表示状態へ畳み込んだドメインモデル。
/// View 側はこの enum を `switch` するだけで映像面・コントロールの出し分けができ、
/// 状態の組み合わせ（写像 = 状態遷移）ロジックはこの型に閉じる。
///
/// 再生エンジン（AVPlayer）は Features 層では扱わず、描画面のバインドは `VideoPlayerProxy` 経由で
/// 行う（docs-internal/architecture.md の Proxy 境界 / Store 方針を参照）。
enum VideoPlayerViewState: Equatable, Sendable {

    /// 再生リソースの取得中（取得前の初期状態を含む）。
    case loading

    /// 端末でローカル再生中（再生可能）。
    case playing

    /// Chromecast へキャスト中。端末側の再生は止め、再生面は Chromecast に一本化する。
    case casting

    /// アセットが見つからない等で再生できない。
    case failed

    /// 再生セッションの進行状態とキャスト有無から表示状態を導出する。
    ///
    /// - `idle` / `loading`: まだ再生できないため `loading`。
    /// - `failed`: 再生不可のため `failed`。
    /// - `ready`: 再生可能。キャスト中なら `casting`、そうでなければ `playing`。
    init(phase: PlaybackStore.Phase, isCasting: Bool) {
        switch phase {
        case .idle, .loading:
            self = .loading
        case .failed:
            self = .failed
        case .ready:
            self = isCasting ? .casting : .playing
        }
    }

    /// 再生可能になった状態か（コントロールを表示してよいか）。
    ///
    /// ローカル再生・キャスト中のいずれも再生中とみなしコントロールを提示する。
    var isReady: Bool {
        switch self {
        case .playing, .casting:
            return true
        case .loading, .failed:
            return false
        }
    }

    /// PIP（ピクチャ・イン・ピクチャ）へ遷移できる状態か。
    ///
    /// キャスト中は再生面を Chromecast に一本化するため不可。ローカル再生中のみ許可する。
    var allowsPictureInPicture: Bool {
        self == .playing
    }
}
