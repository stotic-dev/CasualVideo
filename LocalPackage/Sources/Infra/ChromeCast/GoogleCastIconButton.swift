//
//  GoogleCastIconButton.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/13.
//

// GoogleCast SDK は iOS スライスのみのため、iOS（= GoogleCast を import できる環境）でのみ定義する。
#if canImport(GoogleCast)
import SwiftUI
import GoogleCast

public struct GoogleCastIconButton: UIViewRepresentable {

    public init() {}

    public func makeUIView(context: Context) -> some UIView {
        let castButton = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        return castButton
    }

    public func updateUIView(_ uiView: UIViewType, context: Context) {}
}
#endif
