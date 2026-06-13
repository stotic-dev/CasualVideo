//
//  PlayerModalPresentation.swift
//  Library
//
//  再生画面をモーダル提示するための共通修飾子。
//
//  プレイヤーは全画面モーダル（iOS の fullScreenCover）で提示するが、
//  fullScreenCover は macOS で利用できない。Library ターゲットはテスト実行時に
//  ホスト（macOS）向けにもコンパイルされるため、macOS では sheet にフォールバックして
//  ビルド互換を保つ（実プロダクトは iOS のみ）。
//

import SwiftUI

extension View {

    /// 再生画面をモーダル提示する。iOS は全画面（fullScreenCover）、macOS は sheet。
    func playerCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }
}
