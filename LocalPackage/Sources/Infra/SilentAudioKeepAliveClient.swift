//
//  SilentAudioKeepAliveClient.swift
//  Infra
//
//  AVAudioEngine による無音オーディオ keep-alive の唯一の窓口（single source of truth）。
//
//  Cast 送出中、端末側のローカル再生（AVPlayer）は止まるため、再生中アプリとしての
//  バックグラウンド実行枠（UIBackgroundModes = audio）を保てなくなる。ロック画面・コントロール
//  センターのリモートコマンドを受け取り続け Cast デバイスへ転送するには、無音バッファを
//  ループ再生してオーディオ出力を維持し、バックグラウンドプロセスを生かしておく。
//
//  AVAudioEngine / AVAudioPlayerNode 等のフレームワーク型はこの Client に隔離する
//  （docs-internal/architecture.md「フレームワーク型の隔離」）。iOS 以外（テストランナーの
//  macOS）では型を参照せず no-op とする（`CastClient` と同方針）。
//

#if canImport(AVFAudio) && os(iOS)
import AVFAudio
#endif

/// AVAudioEngine で生成した無音バッファをループ再生し、バックグラウンドプロセスを維持する Client。
///
/// 単一責務（オーディオ出力の維持）に閉じる。Cast の都合は持ち込まず、`start()` / `stop()` の
/// 単純なコマンドのみを公開する。`App` がこれを参照して `SilentAudioKeepAliveProxy` を構築する。
@MainActor
public final class SilentAudioKeepAliveClient {

    #if canImport(AVFAudio) && os(iOS)
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    /// ループ再生する無音バッファ（一度だけ生成して使い回す）。
    private var silentBuffer: AVAudioPCMBuffer?
    /// エンジン・ノードのグラフ接続を一度だけ行ったか。
    private var didAttach = false
    /// 稼働中かどうか（多重 start / stop を避ける）。
    private var isRunning = false
    #endif

    public init() {}

    /// 無音バッファのループ再生を開始する。多重起動は無視する（idempotent）。
    public func start() {
        #if canImport(AVFAudio) && os(iOS)
        guard !isRunning else { return }

        attachIfNeeded()
        guard let buffer = silentBuffer else { return }

        do {
            try engine.start()
        } catch {
            // 起動に失敗しても致命的ではないため握りつぶす（"ながら見"体験を優先）。
            return
        }
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        playerNode.play()
        isRunning = true
        #endif
    }

    /// 無音バッファのループ再生を停止する。多重停止は無視する（idempotent）。
    public func stop() {
        #if canImport(AVFAudio) && os(iOS)
        guard isRunning else { return }
        playerNode.stop()
        engine.stop()
        isRunning = false
        #endif
    }

    // MARK: - Private

    #if canImport(AVFAudio) && os(iOS)
    /// エンジン・ノードのグラフ接続と無音バッファ生成を一度だけ行う。
    private func attachIfNeeded() {
        guard !didAttach else { return }
        didAttach = true

        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        // 1 秒分の無音バッファを生成し、ループ再生でオーディオ出力を維持する。
        let frameCount = AVAudioFrameCount(format.sampleRate)
        if frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) {
            buffer.frameLength = frameCount
            silentBuffer = buffer
        }
    }
    #endif
}
