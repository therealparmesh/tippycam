@preconcurrency import Photos
import Observation
import UIKit

@MainActor
@Observable
final class PhotoLibraryService: NSObject, PHPhotoLibraryChangeObserver {
    private(set) var assets: [PHAsset] = []
    private(set) var latestThumbnail: UIImage?
    private(set) var authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var errorMessage: String?

    @ObservationIgnored
    private let imageManager = PHCachingImageManager()
    @ObservationIgnored
    private var latestThumbnailRequestID: PHImageRequestID?
    @ObservationIgnored
    private var latestAssetIdentifier: String?
    @ObservationIgnored
    private var hasLoadedGalleryAssets = false
    @ObservationIgnored
    private var pendingRefreshTask: Task<Void, Never>?

    var hasReadAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func requestReadAccess() async {
        if authorizationStatus == .notDetermined {
            authorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
        reloadAssets()
    }

    func refresh() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        reloadAssets()
    }

    func refreshLatestThumbnail() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard hasReadAccess else {
            updateLatestThumbnail(with: nil)
            return
        }

        updateLatestThumbnail(with: fetchLatestAsset())
    }

    func save(data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        guard status == .authorized || status == .limited else {
            throw CaptureError.photoLibraryPermissionDenied
        }

        do {
            try await PhotoLibraryChanges.save(data: data)
            refreshAfterLibraryMutation()
        } catch {
            AppLog.photos.error("Photo save failed: \(error.localizedDescription)")
            throw CaptureError.photoSaveFailed
        }
    }

    func delete(_ asset: PHAsset) async throws {
        guard hasReadAccess else {
            throw CaptureError.photoLibraryPermissionDenied
        }

        do {
            try await PhotoLibraryChanges.delete(asset)
            refreshAfterLibraryMutation()
        } catch {
            AppLog.photos.error("Photo deletion failed: \(error.localizedDescription)")
            throw error
        }
    }

    @discardableResult
    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        completion: @escaping @MainActor (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.version = .current
        options.isNetworkAccessAllowed = true

        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { image, info in
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
            let hasError = info?[PHImageErrorKey] != nil
            guard !isCancelled, !hasError else { return }
            Task { @MainActor in
                completion(image)
            }
        }
    }

    func cancelImageRequest(_ requestID: PHImageRequestID) {
        imageManager.cancelImageRequest(requestID)
    }

    @discardableResult
    func requestFullImage(
        for asset: PHAsset,
        completion: @escaping @MainActor (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.version = .current
        options.isNetworkAccessAllowed = true

        return imageManager.requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
            let hasError = info?[PHImageErrorKey] != nil
            guard !isCancelled, !hasError else { return }
            Task { @MainActor in
                completion(image)
            }
        }
    }

    func asset(withIdentifier identifier: String) -> PHAsset? {
        assets.first { $0.localIdentifier == identifier } ?? fetchAsset(withIdentifier: identifier)
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.scheduleRefresh()
        }
    }

    private func scheduleRefresh() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            refreshAfterLibraryMutation()
        }
    }

    private func reloadAssets() {
        hasLoadedGalleryAssets = true

        guard hasReadAccess else {
            assets = []
            updateLatestThumbnail(with: nil)
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        assets = (0..<result.count).map { result.object(at: $0) }
        updateLatestThumbnail(with: assets.first)
    }

    private func refreshAfterLibraryMutation() {
        if hasLoadedGalleryAssets {
            reloadAssets()
        } else {
            refreshLatestThumbnail()
        }
    }

    private func fetchLatestAsset() -> PHAsset? {
        let options = PHFetchOptions()
        options.fetchLimit = 1
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: .image, options: options).firstObject
    }

    private func fetchAsset(withIdentifier identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject
    }

    private func updateLatestThumbnail(with asset: PHAsset?) {
        guard let asset else {
            if let latestThumbnailRequestID {
                imageManager.cancelImageRequest(latestThumbnailRequestID)
                self.latestThumbnailRequestID = nil
            }
            latestAssetIdentifier = nil
            latestThumbnail = nil
            return
        }

        let identifier = asset.localIdentifier
        if latestAssetIdentifier == identifier, latestThumbnail != nil {
            return
        }

        if let latestThumbnailRequestID {
            imageManager.cancelImageRequest(latestThumbnailRequestID)
            self.latestThumbnailRequestID = nil
        }

        latestThumbnail = nil
        latestAssetIdentifier = identifier
        latestThumbnailRequestID = requestImage(
            for: asset,
            targetSize: CGSize(width: 320, height: 320),
            contentMode: .aspectFill
        ) { [weak self] image in
            guard let self, self.latestAssetIdentifier == identifier else { return }
            if let image {
                self.latestThumbnail = image
            }
        }
    }
}

private enum PhotoLibraryChanges {
    static func save(data: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            addPhotoResource(
                data: data,
                creationDate: Date()
            )
        }
    }

    static func delete(_ asset: PHAsset) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }
    }

    private static func addPhotoResource(
        data: Data,
        creationDate: Date
    ) {
        let request = PHAssetCreationRequest.forAsset()
        request.creationDate = creationDate
        let options = PHAssetResourceCreationOptions()
        options.shouldMoveFile = false
        request.addResource(with: .photo, data: data, options: options)
    }
}
