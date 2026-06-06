//
//  VideoLibraryUnauthorizedView.swift
//  Library
//
//  写真ライブラリアクセスが未許可・拒否された場合のフォールバック表示。
//

import Core
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct VideoLibraryUnauthorizedView: View {

    let status: VideoLibraryAuthorizationStatus
    let onRetry: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("写真へのアクセスが必要です", systemImage: "lock.fill")
        } description: {
            Text(message)
        } actions: {
            switch status {
            case .denied:
                #if canImport(UIKit)
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                #else
                EmptyView()
                #endif
            case .notDetermined:
                Button("もう一度試す", action: onRetry)
                    .buttonStyle(.borderedProminent)
            case .restricted, .authorized:
                EmptyView()
            }
        }
    }

    private var message: String {
        switch status {
        case .denied:
            "設定アプリから写真ライブラリへのアクセスを許可してください。"
        case .restricted:
            "デバイスの制限により写真ライブラリにアクセスできません。"
        case .notDetermined:
            "動画を一覧表示するには写真ライブラリへのアクセスを許可してください。"
        case .authorized:
            ""
        }
    }
}
