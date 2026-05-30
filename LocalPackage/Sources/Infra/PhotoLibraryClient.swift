//
//  PhotoLibraryClient.swift
//  Infra
//
//  PhotoKit（写真ライブラリ）との唯一の窓口。
//  許可リクエスト・動画アセット取得・サムネイル取得などプロセス外依存への I/O を閉じ込める。
//

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
    public func loadThumbnail(localIdentifier: String, size: CGSize) async -> CGImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        let manager = PHImageManager.default()
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
