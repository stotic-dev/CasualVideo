//
//  File.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/13.
//

import Core
import Infra
import SwiftUI

extension CastComponentResolver {
    static let live = CastComponentResolver {
        // GoogleCast（iOS スライスのみ）が使える環境では実ボタン、それ以外（macOS のホスト
        // ビルド等）ではプレースホルダにフォールバックし、App をクロスプラットフォームで成立させる。
        #if canImport(GoogleCast)
        GoogleCastIconButton()
        #else
        Image(systemName: "shareplay")
        #endif
    }
}
