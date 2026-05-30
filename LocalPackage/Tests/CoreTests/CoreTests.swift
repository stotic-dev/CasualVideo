//
//  CoreTests.swift
//  CoreTests
//
//  プレースホルダー。Core のロジックテストは implement-test スキルで実装する。
//

import Testing

@testable import Core

@Test func videoLibraryAuthorizationStatusCanAccess() {
    #expect(VideoLibraryAuthorizationStatus.authorized.canAccessLibrary)
    #expect(!VideoLibraryAuthorizationStatus.denied.canAccessLibrary)
    #expect(!VideoLibraryAuthorizationStatus.notDetermined.canAccessLibrary)
    #expect(!VideoLibraryAuthorizationStatus.restricted.canAccessLibrary)
}
