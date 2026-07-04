//
//  SilentAudioKeepAliveProxy.swift
//  Core
//
//  Cast 接続中のバックグラウンドプロセス維持（無音オーディオ keep-alive）を抽象化する Proxy 型定義。
//
//  Chromecast へ送出している間、端末側のローカル再生は止まる（再生面は Cast に一本化）。しかし
//  ロック画面 / コントロールセンターのリモートコマンドを受け取り続け、Cast デバイスへ転送するには、
//  アプリのオーディオ再生プロセスを生かしておく必要がある。そこで無音バッファをループ再生して
//  バックグラウンドプロセスを維持する。Cast 接続中のみ稼働させ、切断で停止する。
//
//  - 抽象化は protocol ではなく struct + クロージャで表現する（docs-internal/architecture.md）。
//  - 型定義は `Core` に置き、本番実装（`.live`）は `App` が `Infra` の Client を用いて構築する。
//  - 本番の AVAudioEngine 操作は `Infra` の Client に隔離する（再生エンジン型の隔離方針）。
//

/// Cast 接続中のバックグラウンド維持（無音オーディオ keep-alive）を抽象化する Proxy。
public struct SilentAudioKeepAliveProxy: Sendable {

    /// 無音オーディオのループ再生を開始し、バックグラウンドプロセスを維持する。
    ///
    /// Cast セッション接続時に呼ぶ。複数回呼ばれても安全（idempotent）。
    public var start: @MainActor @Sendable () -> Void

    /// 無音オーディオのループ再生を停止する。
    ///
    /// Cast セッション切断時・再生セッション破棄時に呼ぶ。複数回呼ばれても安全（idempotent）。
    public var stop: @MainActor @Sendable () -> Void

    public init(
        start: @escaping @MainActor @Sendable () -> Void = {},
        stop: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.start = start
        self.stop = stop
    }
}
