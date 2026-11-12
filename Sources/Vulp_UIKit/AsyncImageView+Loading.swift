#if canImport(UIKit)
import UIKit
@_exported import Vulp

public extension AsyncImageView {
    /// Loads an image source from a URL at this view's current pixel size.
    func loadImage(
        url: URL,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)? = nil
    ) {
        let asset = RemoteMediaAsset(url: url)
        loadImage(
            using: MediaImageLoader.default,
            levelOfIntegrity: levelOfIntegrity,
            prefetchCount: prefetchCount,
            request: { [weak self] targetSize, scale in
                guard let self else { throw CancellationError() }
                let pointSize = targetSize ?? CGSize(
                    width: self.bounds.width.rounded(.up),
                    height: self.bounds.height.rounded(.up)
                )
                guard pointSize.width > 0, pointSize.height > 0 else {
                    throw MediaImageRequestError.invalidTargetSize
                }
                let requestScale = targetSize == nil ? self.traitCollection.displayScale : scale
                return try MediaImageRequest(asset: asset, targetSize: pointSize, scale: requestScale)
            },
            onCompletion: onCompletion
        )
    }

    /// Loads an image asset at an explicit pixel size and plays it when it contains multiple frames.
    func loadImage<Loader: MediaImageLoading>(
        asset: any MediaAsset,
        using loader: Loader = MediaImageLoader.default,
        targetSize: CGSize,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3
    ) async throws {
        let request = try MediaImageRequest(asset: asset, targetSize: targetSize)
        resetForNewImageSource()
        let content = try await Self.loadImageRequest(
            request,
            using: loader,
            levelOfIntegrity: levelOfIntegrity,
            prefetchCount: prefetchCount
        )
        try Task.checkCancellation()
        displayLoadedContent(content, cacheIdentifier: request.cacheIdentifier, notifyCompletion: false)
    }
}
#endif
