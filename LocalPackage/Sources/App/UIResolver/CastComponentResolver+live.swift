//
//  CastComponentResolver+live.swift
//  App
//
//  Cast ボタン UI の本番解決。選択された Cast バックエンドに応じてボタンを差し替える。
//

import Core
import Infra
import SwiftUI

extension CastComponentResolver {

    /// 選択された Cast バックエンドに対応する Cast ボタンを解決する。
    ///
    /// - `.systemRouting`: システム標準のルートピッカー（`AVRoutePickerView`）。
    /// - それ以外（`.googleCast` / `.auto`）: GoogleCast の Cast ボタン。
    ///
    /// GoogleCast / AVKit が使えない環境（macOS のホストビルド等）ではプレースホルダにフォールバックし、
    /// App をクロスプラットフォームで成立させる。
    static func live(backend: CastBackend) -> CastComponentResolver {
        CastComponentResolver {
            if backend == .systemRouting {
                #if canImport(UIKit) && canImport(AVKit)
                SystemRoutePickerView()
                #else
                Image(systemName: "shareplay")
                #endif
            } else {
                #if canImport(GoogleCast)
                GoogleCastIconButton()
                #else
                Image(systemName: "shareplay")
                #endif
            }
        }
    }
}
