//
//  MainScreen.swift
//  Main
//
//  Created by Taichi Sato on 2026/05/30.
//

import SwiftUI

public struct MainScreen: View {
    
    public static func make() -> some View {
        MainScreen()
    }
    
    public var body: some View {
        MainView()
    }
}

struct MainView: View {
    var body: some View {
        Text("Hello World")
    }
}

#Preview {
    MainView()
}
