//
//  CastComponentResolver.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/13.
//

import SwiftUI

public struct CastComponentResolver: Sendable {

    private var _resolve: @MainActor @Sendable () -> AnyView

    public init(
        @ViewBuilder resolve: @escaping @MainActor @Sendable () -> some View
    ) {
        _resolve = {
            AnyView(
                resolve()
                    .frame(width: 12, height: 12)
                    .padding(8)
            )
        }
    }
    
    @MainActor
    public func callAsFunction() -> AnyView {
        _resolve()
    }

}

public extension EnvironmentValues {

    @Entry var castComponentResolver: CastComponentResolver = .preview

}

public extension CastComponentResolver {

    static let preview = CastComponentResolver {
        Image(systemName: "shareplay")
    }

}
