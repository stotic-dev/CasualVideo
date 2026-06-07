//
//  SettingsScreen.swift
//  Library
//
//  再生デフォルト設定（ミュート・再生速度）の編集画面（F-7）。
//
//  ライブラリ画面から開く設定画面のため、Features 同士の依存を避けて Library feature 内に置く。
//
//  Screen と presentational View の分離方針は docs/swiftui.md を参照。
//  - Screen（SettingsScreen）: 共有 Store（SettingsStore）を Environment から取得し、編集（副作用）を委譲する。
//  - View（SettingsView）: init で受け取った設定値と操作クロージャを表示するだけ。副作用を持たない。
//

import Core
import SwiftUI

/// 再生デフォルト設定の編集画面。ライブラリのツールバー（歯車）から push される。
struct SettingsScreen: View {

    /// 再生デフォルト設定の共有 Store（App で assemble・注入）。再生画面とも共有する。
    @Environment(SettingsStore.self) private var store

    var body: some View {
        SettingsView(
            settings: store.settings,
            onSetMuted: { store.setMuted($0) },
            onSetPlaybackRate: { store.setPlaybackRate($0) }
        )
        .navigationTitle("設定")
    }
}

/// 設定画面の presentational View。init で受け取った設定値・操作クロージャを表示するだけで副作用を持たない。
struct SettingsView: View {

    let settings: PlaybackSettings
    let onSetMuted: (Bool) -> Void
    let onSetPlaybackRate: (PlaybackRate) -> Void

    var body: some View {
        Form {
            Section("再生") {
                Toggle(
                    "デフォルトでミュート",
                    isOn: Binding(
                        get: { settings.isMuted },
                        set: { onSetMuted($0) }
                    )
                )

                Picker(
                    "デフォルト再生速度",
                    selection: Binding(
                        get: { settings.playbackRate },
                        set: { onSetPlaybackRate($0) }
                    )
                ) {
                    ForEach(PlaybackRate.allCases) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
            }
        }
    }
}

#if DEBUG

#Preview("デフォルト") {
    NavigationStack {
        SettingsView(
            settings: PlaybackSettings(),
            onSetMuted: { _ in },
            onSetPlaybackRate: { _ in }
        )
        .navigationTitle("設定")
    }
}

#Preview("ミュート解除 + 1.5x") {
    NavigationStack {
        SettingsView(
            settings: PlaybackSettings(isMuted: false, playbackRate: .fast15),
            onSetMuted: { _ in },
            onSetPlaybackRate: { _ in }
        )
        .navigationTitle("設定")
    }
}

#endif
