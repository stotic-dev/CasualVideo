//
//  RemoteCommand.swift
//  Core
//
//  ロック画面・コントロールセンター・外部アクセサリからのリモート操作（F-5）を表すドメイン型。
//

import Foundation

/// Now Playing（ロック画面 / コントロールセンター / イヤホン等）からのリモート再生コマンド。
///
/// システム（MPRemoteCommandCenter）の型は `Infra` に閉じ、`Features`（Store）はこの値型で
/// コマンドを受け取りディスパッチする。`Infra` ローカルのコマンド種別をこの `Core` 型へ
/// 変換する責務は `App` の assemble 層が担う（`PhotoVideoAsset → VideoAsset` と同じ方針）。
public enum RemoteCommand: Sendable, Hashable {

    /// 再生。
    case play

    /// 一時停止。
    case pause

    /// 再生 / 一時停止トグル。
    case toggle

    /// 次の動画へ。
    case next

    /// 前の動画へ。
    case previous

    /// 指定秒へシーク。
    case seek(TimeInterval)
}
