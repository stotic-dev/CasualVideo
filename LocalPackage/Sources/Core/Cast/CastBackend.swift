//
//  CastBackend.swift
//  Core
//
//  Cast の送出バックエンドを表すドメインモデル。
//
//  Cast には 2 つの実装経路がある:
//  - GoogleCast SDK 経路（iOS 26 / メディアデバイス拡張が未導入の環境のフォールバック）。
//  - iOS 27 の `AVSystemRouting` 経路（メディアデバイス拡張経由でシステムのルートピッカーから送出）。
//
//  どちらを使うかは `App` の assemble 層が起動時に 1 つだけ選んで注入する。選択ロジック自体は
//  純粋関数 `resolve(override:isSystemRoutingAvailable:)` として Core に閉じ、テスト可能にする
//  （iOS バージョン / 拡張の利用可否そのものの判定は呼び出し側が `isSystemRoutingAvailable` で渡す）。
//

/// Cast の送出バックエンド。
public enum CastBackend: String, Sendable, CaseIterable {

    /// 環境に応じて自動選択する（既定）。
    case auto

    /// GoogleCast SDK 経路。
    case googleCast

    /// iOS 27 `AVSystemRouting` 経路。
    case systemRouting

    /// 開発者向けの表示名。
    public var displayName: String {
        switch self {
        case .auto: "自動"
        case .googleCast: "GoogleCast SDK"
        case .systemRouting: "AVSystemRouting (iOS 27)"
        }
    }

    /// 手動 override と利用可否から、実際に使うバックエンドを導出する。
    ///
    /// - `auto`: `AVSystemRouting` が使えるなら `.systemRouting`、そうでなければ `.googleCast`。
    /// - `googleCast` / `systemRouting`: 明示指定をそのまま採用する（開発者モードでの手動切り替え）。
    ///
    /// - Parameters:
    ///   - override: 開発者モードで選択されたバックエンド（既定 `.auto`）。
    ///   - isSystemRoutingAvailable: iOS 27 以上かつメディアデバイス拡張が利用可能か。
    ///     OS バージョン判定と `AVSystemRouteController.supportedExtensionAvailable` の評価は
    ///     呼び出し側（App）が行い、その結果をここへ渡す。
    public static func resolve(override: CastBackend, isSystemRoutingAvailable: Bool) -> CastBackend {
        switch override {
        case .auto:
            return isSystemRoutingAvailable ? .systemRouting : .googleCast
        case .googleCast:
            return .googleCast
        case .systemRouting:
            return .systemRouting
        }
    }
}
