//
//  SettingsScreen.swift
//  Library
//
//  再生デフォルト設定（ミュート・再生速度）の編集画面（F-7）。
//
//  ライブラリ画面から開く設定画面のため、Features 同士の依存を避けて Library feature 内に置く。
//
//  Screen と presentational View の分離方針は docs/swiftui.md を参照。
//  - Screen（SettingsScreen）: Environment から Repository を取得し Store を生成、副作用（永続化）を担う。
//  - View（SettingsView）: init で受け取った設定値と操作クロージャを表示するだけ。副作用を持たない。
//

import Core
import SwiftUI

/// 再生デフォルト設定の編集画面。ライブラリのツールバー（歯車）から push される。
struct SettingsScreen: View {

    @Environment(\.playbackSettingsRepository) private var repository

    /// 設定の編集・永続化を担う Store。設定画面のライフサイクルに紐づくため View 層で生成・保持する。
    @State private var store: SettingsStore?

    var body: some View {
        SettingsView(
            settings: store?.settings ?? PlaybackSettings(),
            onSetMuted: { store?.setMuted($0) },
            onSetPlaybackRate: { store?.setPlaybackRate($0) }
        )
        .navigationTitle("設定")
        .task {
            // Repository は Environment 経由で受け取り、Store の生成・初期読み込みは Screen で行う。
            if store == nil {
                store = SettingsStore(repository: repository)
            }
        }
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
