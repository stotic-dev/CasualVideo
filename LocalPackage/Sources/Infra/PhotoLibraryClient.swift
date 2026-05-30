//
//  PhotoLibraryClient.swift
//  Infra
//
//  PhotoKit（写真ライブラリ）との唯一の窓口。
//  許可リクエスト・動画アセット取得・サムネイル取得などプロセス外依存への I/O を閉じ込める。
//

import AVFoundation
import CoreGraphics
import Foundation
import Photos

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 写真ライブラリ上の動画アセットの正規化済み情報。
///
/// `Infra` は PhotoKit 由来の値を素直な値型へ変換して `App` に渡す。
/// `Core` のドメインモデルへの変換は `App`（assemble 層）が担う。
public struct PhotoVideoAsset: Sendable, Hashable {
    public let localIdentifier: String
    public let duration: TimeInterval
    public let creationDate: Date?
    public let isInCloud: Bool
}

/// 写真ライブラリへのアクセス許可状態（PhotoKit 由来）。
public enum PhotoLibraryAuthorization: Sendable, Hashable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// PhotoKit と直接やりとりするクライアント。
public struct PhotoLibraryClient: Sendable {

    /// サムネイル取得とそのメモリキャッシュを担う。
    private let thumbnails = ThumbnailImageManager()

    public init() {}

    /// 現在のアクセス許可状態を返す。
    public func currentAuthorization() -> PhotoLibraryAuthorization {
        Self.normalize(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// アクセス許可をリクエストし、結果の許可状態を返す。
    public func requestAuthorization() async -> PhotoLibraryAuthorization {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return Self.normalize(status)
    }

    /// 写真ライブラリ内の全動画アセットを撮影日の新しい順で取得する。
    public func fetchVideos() -> [PhotoVideoAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let result = PHAsset.fetchAssets(with: options)
        var assets: [PhotoVideoAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(
                PhotoVideoAsset(
                    localIdentifier: asset.localIdentifier,
                    duration: asset.duration,
                    creationDate: asset.creationDate,
                    // ローカルに無い = iCloud 上にあると判定する。
                    isInCloud: !asset.isLocallyAvailable
                )
            )
        }
        return assets
    }

    /// 指定アセットのサムネイルを非同期に取得する。iCloud 上の動画も取得対象とする。
    ///
    /// 同一 `id + size` の再取得はメモリキャッシュから返すため、再表示・スクロール往復で
    /// PhotoKit への問い合わせは発生しない。
    public func loadThumbnail(localIdentifier: String, size: CGSize) async -> CGImage? {
        await thumbnails.thumbnail(localIdentifier: localIdentifier, size: size)
    }

    /// 指定アセットの再生用 `AVPlayerItem` を非同期に取得する（F-2）。
    ///
    /// iCloud 上の動画もネットワーク経由で再生できるよう `isNetworkAccessAllowed` を有効にする。
    /// 取得できない（アセットが存在しない／再生不可）場合は nil。
    public func loadPlayerItem(localIdentifier: String) async -> sending AVPlayerItem? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        let box: PlayerItemBox = await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: PlayerItemBox(item: item))
            }
        }
        return box.item
    }

    private static func normalize(_ status: PHAuthorizationStatus) -> PhotoLibraryAuthorization {
        switch status {
        case .authorized, .limited:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .notDetermined:
            .notDetermined
        @unknown default:
            .denied
        }
    }
}

/// 非 Sendable な `AVPlayerItem` を `withCheckedContinuation` の境界越しに受け渡すためのボックス。
///
/// PhotoKit のコールバックは任意のキューで呼ばれるため、結果を一旦この Sendable な箱に詰めてから
/// 呼び出し側へ返す。`AVPlayerItem` は単一参照で外部共有しないため `@unchecked Sendable` とする。
private struct PlayerItemBox: @unchecked Sendable {
    let item: AVPlayerItem?
}

/// サムネイルの取得と、`localIdentifier + size` をキーにしたメモリキャッシュを担う。
///
/// `NSCache` / `PHCachingImageManager` はいずれもスレッドセーフなため、
/// 値型 `PhotoLibraryClient` から安全に共有できるよう `@unchecked Sendable` とする。
private final class ThumbnailImageManager: @unchecked Sendable {

    /// 取得済みサムネイルのメモリキャッシュ。メモリ逼迫時は OS が自動で破棄する。
    private let cache = NSCache<NSString, CGImage>()

    /// PhotoKit の画像取得マネージャ。将来の先読み（startCachingImages）拡張も見据えて保持する。
    private let manager = PHCachingImageManager()

    /// サムネイルを返す。キャッシュにあれば PhotoKit へ問い合わせず即座に返す。
    func thumbnail(localIdentifier: String, size: CGSize) async -> CGImage? {
        let key = Self.cacheKey(localIdentifier: localIdentifier, size: size)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let image = await requestImage(for: asset, size: size)
        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    private func requestImage(for asset: PHAsset, size: CGSize) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        return await withCheckedContinuation { continuation in
            var didResume = false
            manager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // opportunistic では低解像度の暫定画像で複数回呼ばれることがあるため、
                // 縮退（degraded）でない最終結果のみ採用する。
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: image?.toCGImage())
            }
        }
    }

    /// 同一アセットでもサイズが異なれば別画像として扱う。
    private static func cacheKey(localIdentifier: String, size: CGSize) -> NSString {
        "\(localIdentifier)#\(Int(size.width))x\(Int(size.height))" as NSString
    }
}

#if canImport(UIKit)
extension UIImage {
    fileprivate func toCGImage() -> CGImage? { cgImage }
}
#elseif canImport(AppKit)
extension NSImage {
    fileprivate func toCGImage() -> CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
#endif

extension PHAsset {
    /// 端末ローカルにアセット実体が存在するか（おおよその判定）。
    fileprivate var isLocallyAvailable: Bool {
        let resources = PHAssetResource.assetResources(for: self)
        guard !resources.isEmpty else { return true }
        return resources.contains { resource in
            (resource.value(forKey: "locallyAvailable") as? Bool) ?? true
        }
    }
}
