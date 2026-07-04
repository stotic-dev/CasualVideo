//
//  CastSessionState.swift
//  Core
//
//  Chromecast セッションの接続状態を表すドメインモデル。
//
//  Cast SDK（GoogleCast）の `GCKConnectionState` 等の具体型には依存せず、`Core` で完結する
//  値型として定義する。`Features` / Store はこの型を介して Cast の接続状態を扱う。
//

/// Chromecast セッションの接続状態。
///
/// `Infra` の Cast Client が SDK 由来のイベントをこの値へ正規化し、`CastProxy` 経由で通知する。
public enum CastSessionState: Sendable, Equatable {
    /// 未接続。
    case disconnected
    /// 接続済み（メディアをロードして再生できる）。
    case connected
}
