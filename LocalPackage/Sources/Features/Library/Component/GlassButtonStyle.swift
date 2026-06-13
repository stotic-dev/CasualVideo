//
//  GlassButtonStyle.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/13.
//

import SwiftUI

extension View {
    func glassButtonStyle() -> some View {
        self.modifier(GlassButtonStyle())
    }
    
    func glassEffectStyle() -> some View {
        self.modifier(GlassEffectStyle())
    }
}

struct GlassButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
        } else {
            content
        }
    }
}

struct GlassEffectStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: .rect(cornerRadius: 20))
        } else {
            content
        }
    }
}
