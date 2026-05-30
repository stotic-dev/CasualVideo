//
//  RootScreen.swift
//  App
//
//  アプリのルート画面。依存を assemble し、Environment へ DI する。
//

import Core
import Library
import SwiftUI

public struct RootScreen: View {

    public static func make() -> some View {
        RootScreen()
    }

    public init() {}

    public var body: some View {
        VideoLibraryScreen.make()
            // Infra を用いて構築した本番 Repository を DI する。
            .environment(\.videoLibraryRepository, .live())
    }
}
