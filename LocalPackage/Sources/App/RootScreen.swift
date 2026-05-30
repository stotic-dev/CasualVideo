//
//  RootScreen.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/05/30.
//

import SwiftUI
import Main

public struct RootScreen: View {
    
    public static func make() -> some View {
        RootScreen()
    }
    
    public var body: some View {
        MainScreen.make()
    }
}
