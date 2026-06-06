//
//  PlaybackMode.swift
//  Core
//
//  プレイリストの再生モード（F-5: シャッフル / リピート）を表すドメイン型。
//

import Foundation

/// プレイリストの再生順序モード（F-5 / requirements 3.2）。
///
/// 「連続（順番どおり）」「シャッフル（ランダムな順序）」を切り替える。
/// リピートの有無は `RepeatMode` で直交して扱う。
public enum PlaybackOrder: Sendable, Hashable, CaseIterable {

    /// プレイリストの並び順どおりに再生する（F-4 の既定）。
    case sequential

    /// プレイリストをシャッフルした順序で再生する。
    case shuffle
}

/// プレイリストのリピートモード（F-5 / requirements 3.2）。
public enum RepeatMode: Sendable, Hashable, CaseIterable {

    /// リピートしない。末尾まで再生したら停止する。
    case off

    /// プレイリスト全体を繰り返す。末尾の次は先頭へ戻る。
    case all

    /// 現在の 1 動画を繰り返す。
    case one

    /// トグル操作用に次のリピートモード（off → all → one → off）を返す。
    public var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}
