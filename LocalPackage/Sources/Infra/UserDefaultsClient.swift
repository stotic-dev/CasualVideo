//
//  UserDefaultsClient.swift
//  Infra
//
//  UserDefaults への永続化を隔離する単一責務クライアント（F-7）。
//
//  プロセス外依存（UserDefaults）との唯一の窓口。read/write をここに閉じ込める。
//  「どのキーをどのドメイン型へ対応づけるか」という使う側の都合は持たず、プリミティブな
//  get/set だけを公開する（Infra Client の責務境界 / docs/architecture.md）。
//  ドメイン型（PlaybackSettings 等）への対応づけは `App` の Repository.live が担う。
//

import Foundation

/// UserDefaults による永続化クライアント。プリミティブ値の read/write のみを公開する。
///
/// `UserDefaults` はスレッドセーフなため `@unchecked Sendable` とする。
public struct UserDefaultsClient: @unchecked Sendable {

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 指定キーの `Bool` を返す。未設定なら nil。
    public func bool(forKey key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    /// 指定キーへ `Bool` を保存する。
    public func setBool(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    /// 指定キーの `Double` を返す。未設定なら nil。
    public func double(forKey key: String) -> Double? {
        defaults.object(forKey: key) as? Double
    }

    /// 指定キーへ `Double` を保存する。
    public func setDouble(_ value: Double, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    /// 指定キーの `String` を返す。未設定なら nil。
    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    /// 指定キーへ `String` を保存する。
    public func setString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}
