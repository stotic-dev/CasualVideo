//
//  IsPreview+Environment.swift
//  Core
//
//  SwiftUI Preview 実行中かどうかを示す Environment フラグの定義。
//
//  Preview では再生エンジン（AVPlayer / AVPlayerLayer）が動作しないため、再生ビューはモックアップ UI を
//  表示する必要がある。標準の `EnvironmentValues` には Preview 判定の口が無いため、横断的に参照できる
//  フラグを Core に定義し、Preview 側で `.environment(\.isPreview, true)` を注入する。
//

import SwiftUI

extension EnvironmentValues {

    /// SwiftUI Preview 実行中かどうか。
    ///
    /// 既定は `false`（本番・実行時）。Preview では明示的に `true` を注入し、再生ビュー等が
    /// 実デバイス依存（再生エンジン）の代わりにモックアップ UI を表示できるようにする。
    @Entry public var isPreview = false
}
