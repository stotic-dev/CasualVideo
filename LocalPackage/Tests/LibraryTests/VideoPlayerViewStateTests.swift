//
//  VideoPlayerViewStateTests.swift
//  LibraryTests
//
//  再生セッションの進行状態 + キャスト有無 → 表示状態への写像（状態遷移）ロジックを検証する。
//

import Testing

@testable import Library

@Test("idle は loading 表示になる（キャスト有無に関わらず）")
func videoPlayerViewState_fromIdle_isLoading() {
    #expect(VideoPlayerViewState(phase: .idle, isCasting: false) == .loading)
    #expect(VideoPlayerViewState(phase: .idle, isCasting: true) == .loading)
}

@Test("loading は loading 表示になる（キャスト有無に関わらず）")
func videoPlayerViewState_fromLoading_isLoading() {
    #expect(VideoPlayerViewState(phase: .loading, isCasting: false) == .loading)
    #expect(VideoPlayerViewState(phase: .loading, isCasting: true) == .loading)
}

@Test("failed は failed 表示になる（キャスト有無に関わらず）")
func videoPlayerViewState_fromFailed_isFailed() {
    #expect(VideoPlayerViewState(phase: .failed, isCasting: false) == .failed)
    #expect(VideoPlayerViewState(phase: .failed, isCasting: true) == .failed)
}

@Test("ready かつ非キャストは playing 表示になる")
func videoPlayerViewState_fromReadyNotCasting_isPlaying() {
    #expect(VideoPlayerViewState(phase: .ready, isCasting: false) == .playing)
}

@Test("ready かつキャスト中は casting 表示になる")
func videoPlayerViewState_fromReadyCasting_isCasting() {
    #expect(VideoPlayerViewState(phase: .ready, isCasting: true) == .casting)
}

@Test("isReady は playing / casting のときのみ true")
func videoPlayerViewState_isReady() {
    #expect(VideoPlayerViewState.playing.isReady)
    #expect(VideoPlayerViewState.casting.isReady)
    #expect(!VideoPlayerViewState.loading.isReady)
    #expect(!VideoPlayerViewState.failed.isReady)
}

@Test("PIP は playing のときのみ許可される")
func videoPlayerViewState_allowsPictureInPicture() {
    #expect(VideoPlayerViewState.playing.allowsPictureInPicture)
    #expect(!VideoPlayerViewState.casting.allowsPictureInPicture)
    #expect(!VideoPlayerViewState.loading.allowsPictureInPicture)
    #expect(!VideoPlayerViewState.failed.allowsPictureInPicture)
}
