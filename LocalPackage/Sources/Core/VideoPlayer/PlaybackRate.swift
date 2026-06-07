//
//  PlaybackRate.swift
//  Core
//
//  再生速度を表すドメイン型（F-7 再生速度切り替え）。
//
//  再生画面（速度選択 Menu）と設定画面（デフォルト速度 Picker）の複数 Feature、および
//  Repository（永続化）から参照されるため Core に置く（配置スコープ最小化の原則: 共有されるため Core が適切）。
//

import Foundation

/// 再生速度。再生エンジン（AVPlayer）の rate 値（`Double`）をドメインの選択肢として表現する。
///
/// 再生エンジンの型は扱わず、選択肢を列挙した値型のみで表す。実際の rate 反映は
/// `VideoPlayerProxy.setRate` 経由で `Infra` に隔離する。
public enum PlaybackRate: Double, Sendable, Hashable, CaseIterable, Identifiable {
    case normal = 1.0
    case fast12 = 1.2
    case fast15 = 1.5
    case double = 2.0

    public var id: Double { rawValue }

    /// UI 表示用のラベル（例 "1.0x"）。
    public var displayName: String {
        switch self {
        case .normal: "1.0x"
        case .fast12: "1.2x"
        case .fast15: "1.5x"
        case .double: "2.0x"
        }
    }
}
