//
//  SystemRoutePickerView.swift
//  Infra
//
//  システム標準のルートピッカー（`AVRoutePickerView`）を SwiftUI へ橋渡しする。
//
//  iOS 27 + メディアデバイス拡張（MDE）導入時、このピッカーに第三者デバイス（Chromecast 等）が
//  表示される。`GoogleCastIconButton`（GoogleCast 経路の Cast ボタン）と対になる、`AVSystemRouting`
//  経路の Cast ボタン。
//
//  AVKit / UIKit が使える環境（iOS）でのみ定義する。macOS のホストビルドでは未定義となり、
//  `App` の `CastComponentResolver` がプレースホルダへフォールバックする。
//

#if canImport(UIKit) && canImport(AVKit)
import SwiftUI
import AVKit

public struct SystemRoutePickerView: UIViewRepresentable {

    public init() {}

    public func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        // 再生画面の暗背景に合わせて白基調にする。
        picker.tintColor = .white
        picker.activeTintColor = .systemBlue
        return picker
    }

    public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
