//
//  VideoLibraryStoreTests.swift
//  LibraryTests
//
//  VideoLibraryStore のロード状態遷移ロジックを検証する。
//

import Core
import Foundation
import Testing

@testable import Library

// MARK: - Helpers

private func makeAsset(id: String) -> VideoAsset {
    VideoAsset(id: id, duration: 1, creationDate: nil, isInCloud: false)
}

// MARK: - load()

@MainActor
@Test("未確認状態のとき許可リクエストを行い、許可されたら一覧をロードする")
func load_whenNotDetermined_requestsAndLoads() async {
    let assets = [makeAsset(id: "a"), makeAsset(id: "b")]
    let repository = VideoLibraryRepository(
        authorizationStatus: { .notDetermined },
        requestAuthorization: { .authorized },
        fetchVideos: { assets }
    )
    let store = VideoLibraryStore(repository: repository)

    await store.load()

    #expect(store.loadState == .loaded(assets))
}

@MainActor
@Test("既に許可済みのときはリクエストせず一覧をロードする")
func load_whenAlreadyAuthorized_loadsWithoutRequest() async {
    let assets = [makeAsset(id: "a")]
    let requested = Mutable(false)
    let repository = VideoLibraryRepository(
        authorizationStatus: { .authorized },
        requestAuthorization: {
            requested.value = true
            return .authorized
        },
        fetchVideos: { assets }
    )
    let store = VideoLibraryStore(repository: repository)

    await store.load()

    #expect(store.loadState == .loaded(assets))
    #expect(requested.value == false)
}

@MainActor
@Test("拒否状態のときは unauthorized になり一覧を取得しない")
func load_whenDenied_setsUnauthorized() async {
    let fetched = Mutable(false)
    let repository = VideoLibraryRepository(
        authorizationStatus: { .denied },
        fetchVideos: {
            fetched.value = true
            return []
        }
    )
    let store = VideoLibraryStore(repository: repository)

    await store.load()

    #expect(store.loadState == .unauthorized(.denied))
    #expect(fetched.value == false)
}

@MainActor
@Test("未確認からリクエストして拒否されたら unauthorized になる")
func load_whenNotDeterminedThenDenied_setsUnauthorized() async {
    let repository = VideoLibraryRepository(
        authorizationStatus: { .notDetermined },
        requestAuthorization: { .denied }
    )
    let store = VideoLibraryStore(repository: repository)

    await store.load()

    #expect(store.loadState == .unauthorized(.denied))
}

@MainActor
@Test("既に loaded のときは再取得せず状態を維持する")
func load_whenAlreadyLoaded_doesNotRefetch() async {
    let firstAssets = [makeAsset(id: "first")]
    let callCount = Mutable(0)
    let repository = VideoLibraryRepository(
        authorizationStatus: { .authorized },
        fetchVideos: {
            callCount.value += 1
            return firstAssets
        }
    )
    let store = VideoLibraryStore(repository: repository)

    await store.load()
    await store.load()

    #expect(store.loadState == .loaded(firstAssets))
    #expect(callCount.value == 1)
}

// MARK: - reload()

@MainActor
@Test("reload は許可状態を再確認して一覧を取り直す")
func reload_whenAuthorized_refetches() async {
    let assets = Mutable([makeAsset(id: "old")])
    let repository = VideoLibraryRepository(
        authorizationStatus: { .authorized },
        fetchVideos: { assets.value }
    )
    let store = VideoLibraryStore(repository: repository)

    await store.load()
    #expect(store.loadState == .loaded([makeAsset(id: "old")]))

    assets.value = [makeAsset(id: "new")]
    await store.reload()

    #expect(store.loadState == .loaded([makeAsset(id: "new")]))
}

@MainActor
@Test("reload 時に許可されていなければ unauthorized になる")
func reload_whenNotAuthorized_setsUnauthorized() async {
    let repository = VideoLibraryRepository(
        authorizationStatus: { .restricted }
    )
    let store = VideoLibraryStore(repository: repository)

    await store.reload()

    #expect(store.loadState == .unauthorized(.restricted))
}

// MARK: - Test utility

/// クロージャ内から書き換え可能な参照ボックス。
/// @MainActor 上のテストでのみ使用するため Sendable 制約は付けない。
private final class Mutable<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
