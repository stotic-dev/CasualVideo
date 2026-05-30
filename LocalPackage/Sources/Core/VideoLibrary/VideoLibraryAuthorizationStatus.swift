//
//  VideoLibraryAuthorizationStatus.swift
//  Core
//
//  写真ライブラリへのアクセス許可状態を表すドメインモデル。
//

import Foundation

/// 写真ライブラリへのアクセス許可状態。
///
/// PhotoKit の `PHAuthorizationStatus` に依存せず、アプリ内で扱いやすい形に正規化する。
public enum VideoLibraryAuthorizationStatus: Sendable, Hashable {

    /// 未確認（まだリクエストしていない）。
    case notDetermined

    /// 全アクセスまたは一部アクセスが許可されている。
    case authorized

    /// 拒否されている。
    case denied

    /// 機能制限などで利用不可。
    case restricted

    /// 動画一覧を取得・表示できる状態かどうか。
    public var canAccessLibrary: Bool {
        self == .authorized
    }
}
