//
//  CastBackendTests.swift
//  CoreTests
//
//  Cast バックエンドの選択ロジック（override × 利用可否 → 実バックエンド）を検証する。
//

import Testing

@testable import Core

@Test("auto かつ AVSystemRouting 利用可なら systemRouting")
func castBackend_resolveAutoWhenAvailable_isSystemRouting() {
    #expect(CastBackend.resolve(override: .auto, isSystemRoutingAvailable: true) == .systemRouting)
}

@Test("auto かつ AVSystemRouting 利用不可なら googleCast")
func castBackend_resolveAutoWhenUnavailable_isGoogleCast() {
    #expect(CastBackend.resolve(override: .auto, isSystemRoutingAvailable: false) == .googleCast)
}

@Test("googleCast の明示指定は利用可否に関わらず googleCast")
func castBackend_resolveExplicitGoogleCast_isGoogleCast() {
    #expect(CastBackend.resolve(override: .googleCast, isSystemRoutingAvailable: true) == .googleCast)
    #expect(CastBackend.resolve(override: .googleCast, isSystemRoutingAvailable: false) == .googleCast)
}

@Test("systemRouting の明示指定は利用可否に関わらず systemRouting")
func castBackend_resolveExplicitSystemRouting_isSystemRouting() {
    #expect(CastBackend.resolve(override: .systemRouting, isSystemRoutingAvailable: true) == .systemRouting)
    #expect(CastBackend.resolve(override: .systemRouting, isSystemRoutingAvailable: false) == .systemRouting)
}
