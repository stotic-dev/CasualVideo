//
//  NowPlayingInfoProxy.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/06.
//

import Foundation
import SwiftUI

public struct NowPlayingInfoProxy {
    /// Now Playing 情報（ロック画面 / コントロールセンター / F-5）を更新する。
    ///
    /// タイトル・再生時間・再生位置・再生状態を即時反映し、アートワーク（動画サムネイル）は
    /// `assetID` が変わったときのみ非同期取得する。MediaPlayer の型は `Infra` に隔離する。
    public var updateNowPlayingInfo: @MainActor @Sendable (_ info: NowPlayingInfo) -> Void

    /// Now Playing 情報をクリアする（再生終了・離脱時 / F-5）。
    public var clearNowPlayingInfo: @MainActor @Sendable () -> Void
    
    /// リモートコマンド（ロック画面等の操作 / F-5）を購読する。コマンドのたびにハンドラが呼ばれる。
    ///
    /// システム（MPRemoteCommandCenter）のコマンドハンドラ登録は `Infra` に隔離する。
    public var observeRemoteCommand: @MainActor @Sendable (_ handler: @escaping @MainActor @Sendable (RemoteCommand) -> Void) -> Void
    
    public init(
        updateNowPlayingInfo: @MainActor @Sendable @escaping (_: NowPlayingInfo) -> Void = { _ in },
        clearNowPlayingInfo: @MainActor @Sendable @escaping () -> Void = {},
        observeRemoteCommand: @MainActor @escaping @Sendable (_ handler: @escaping @MainActor @Sendable (RemoteCommand) -> Void) -> Void = { _ in }
    ) {
        self.updateNowPlayingInfo = updateNowPlayingInfo
        self.clearNowPlayingInfo = clearNowPlayingInfo
        self.observeRemoteCommand = observeRemoteCommand
    }
}

extension EnvironmentValues {

    /// NowPlayingInfoProxy の DI エントリ。
    ///
    /// 本番インスタンスは `App` で実装
    /// 未注入時は何もしない（再生不可・操作は no-op）フォールバック。
    @Entry public var nowPlayingInfoProxy = NowPlayingInfoProxy()
}
