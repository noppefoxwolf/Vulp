import Foundation
import CoreGraphics

/// Commonly used image loaders.
public enum MediaImageLoader {
    /// A shared loader using URLSession, ImageIO, AVFoundation, image resizing, and in-memory caching.
    public static let `default`: DefaultMediaImageLoader = DefaultMediaImageLoader(
        downloader: DefaultAssetDataDownloader(),
        decoders: [ImageIOImageDecoder(), AVFoundationVideoFrameDecoder()],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
}


public struct DefaultMediaImageLoader: MediaImageSequenceLoading {
    private let downloader: any AssetDataDownloader
    private let decoders: [any MediaImageDecoding]
    private let processor: any ImageProcessor
    private let cache: any ImageCache
    private let assetDataResultCache: AssetDataResultCache
    private let fetchDeduper = TaskDeduper<String, MediaImage>()
    private let sourceFileDeduper = TaskDeduper<String, AssetSourceFile>()
    private let usesDiskDataCache: Bool

    /// Removes all decoded images and encoded source data stored by this loader.
    public func clearCache() async {
        await cache.removeAllImages()
        await assetDataResultCache.removeAll()
    }

    /// Creates a loader with an ordered list of decoders.
    public init<Downloader: AssetDataDownloader, Processor: ImageProcessor, Cache: ImageCache>(
        downloader: Downloader,
        decoders: [any MediaImageDecoding],
        processor: Processor,
        cache: Cache,
        dataCache: any AssetDataCache = DiskAssetDataCache()
    ) {
        self.downloader = downloader
        self.usesDiskDataCache = dataCache is DiskAssetDataCache
        self.decoders = decoders
        self.processor = processor
        self.cache = cache
        self.assetDataResultCache = AssetDataResultCache(dataCache: dataCache)
    }

    @concurrent
    public func load<Request: MediaImageRequestProtocol>(
        _ request: Request,
        priority: TaskPriority = .userInitiated
    ) async throws -> MediaImage {
        try await load(request, process: { image in
            try await processor.process(image, for: request)
        }, priority: priority)
    }

    /// Prefetches only the encoded source asset, without decoding or processing an image.
    public func prefetch(
        _ asset: any MediaAsset,
        priority: TaskPriority
    ) -> Task<Void, Never> {
        let task = Task(priority: priority) { [self] in
            do {
                _ = try await sourceFile(for: asset, priority: priority)
            } catch is CancellationError {
                // Cancellation is expected when a prefetched item leaves the
                // collection's visible prefetch window.
            } catch {
                // A visible load can retry and report the failure to the UI.
            }
        }
        return task
    }

    private func load<Request: MediaImageRequestProtocol>(
        _ request: Request,
        process: @escaping @Sendable (MediaImage) async throws -> MediaImage,
        priority: TaskPriority = .userInitiated
    ) async throws -> MediaImage {
        if let cached = await cache.image(forKey: request.cacheIdentifier) {
            return cached
        }

        return try await fetchDeduper.load(forKey: request.cacheIdentifier, priority: priority) {
            let (image, usedFallback) = try await loadUncached(request, process: process, priority: priority)
            if !usedFallback {
                await cache.insert(image, forKey: request.cacheIdentifier)
            }
            return image
        }
    }

    private func loadUncached<Request: MediaImageRequestProtocol>(
        _ request: Request,
        process: @Sendable (MediaImage) async throws -> MediaImage,
        priority: TaskPriority
    ) async throws -> (MediaImage, usedFallback: Bool) {
        let longestTargetEdge = max(request.targetSize.width, request.targetSize.height)
        // This caps decoder output; the processor fits the decoded image within `request.targetSize`.
        let maximumPixelDimension: Int? = {
            guard longestTargetEdge.isFinite,
                  longestTargetEdge > 0,
                  longestTargetEdge < CGFloat(Int.max)
            else { return nil }
            return Int(longestTargetEdge.rounded(.up))
        }()

        let asset = request.asset
        let image: MediaImage
        let usedFallback: Bool
        do {
            try Task.checkCancellation()
            let source = try await sourceFile(for: asset, priority: priority)
            defer { withExtendedLifetime(source) {} }
            try Task.checkCancellation()
            let sourceURL = source.url
            let sourceDecoders = await decoders(for: sourceURL)
            guard !sourceDecoders.isEmpty else {
                throw MediaImageDecodingError.unsupportedSource
            }
            image = try await decode(
                from: sourceURL,
                using: sourceDecoders,
                request: request,
                maximumPixelDimension: maximumPixelDimension
            )
            usedFallback = false
        } catch {
            try Task.checkCancellation()
            guard let fallback = asset.fallbackImage else { throw error }
            image = fallback
            usedFallback = true
        }

        try Task.checkCancellation()
        return (try await process(image), usedFallback)
    }

    private func decode<Request: MediaImageRequestProtocol>(
        from url: URL,
        using decoders: [any MediaImageDecoding],
        request: Request,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        for decoder in decoders {
            do {
                return try await decoder.decode(
                    from: url,
                    options: request.decodingOptions,
                    maximumPixelDimension: maximumPixelDimension
                )
            } catch MediaImageDecodingError.unsupportedSource {
                continue
            }
        }
        throw MediaImageDecodingError.unsupportedSource
    }

    @concurrent
    private func sourceFile(
        for asset: any MediaAsset,
        priority: TaskPriority
    ) async throws -> AssetSourceFile {
        if let cachedURL = await assetDataResultCache.fileURL(forKey: asset.uniqueKey) {
            return AssetSourceFile(url: cachedURL)
        }
        if let error = await assetDataResultCache.failure(forKey: asset.uniqueKey) {
            guard shouldRetry(after: error) else { throw error }
            await assetDataResultCache.removeFailure(forKey: asset.uniqueKey)
        }

        return try await sourceFileDeduper.load(forKey: asset.uniqueKey, priority: priority) { [self] in
            do {
                if let cachedURL = await assetDataResultCache.fileURL(forKey: asset.uniqueKey) {
                    return AssetSourceFile(url: cachedURL)
                }
                try Task.checkCancellation()
                if usesDiskDataCache, let remote = asset as? RemoteMediaAsset,
                   let downloader = downloader as? DefaultAssetDataDownloader {
                    let downloaded = try await downloader.downloadFile(from: remote.url)
                    if let cached = await assetDataResultCache.moveFile(at: downloaded, forKey: asset.uniqueKey) {
                        return AssetSourceFile(url: cached)
                    }
                    return AssetSourceFile(url: downloaded, isTemporary: true)
                }

                let data = try await asset.loadData(using: downloader)
                if let cached = await assetDataResultCache.insert(data, forKey: asset.uniqueKey) {
                    return AssetSourceFile(url: cached)
                }

                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Vulp-\(UUID().uuidString)", isDirectory: false)
                try data.write(to: url, options: .atomic)
                return AssetSourceFile(url: url, isTemporary: true)
            } catch {
                if !isCancellation(error) {
                    await assetDataResultCache.insertFailure(error, forKey: asset.uniqueKey)
                }
                throw error
            }
        }
    }

    private func shouldRetry(after error: Error) -> Bool {
        if let downloadError = error as? AssetDownloadError {
            switch downloadError {
            case .unsupportedAsset, .exceedsMaximumSize:
                return false
            case .unacceptableStatusCode(let statusCode):
                return statusCode == 408 || statusCode == 425 || statusCode == 429 || (500..<600).contains(statusCode)
            case .invalidResponse:
                return true
            }
        }

        return true
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func sequenceCapableDecoder(for url: URL, data: Data) async -> (any MediaImageDecoding)? {
        for decoder in decoders {
            guard await decoder.canDecode(url: url),
                  await decoder.canDecodeSequence(data: data)
            else { continue }
            return decoder
        }
        return nil
    }

    private func decoders(for url: URL) async -> [any MediaImageDecoding] {
        var matchingDecoders: [any MediaImageDecoding] = []
        for decoder in decoders where await decoder.canDecode(url: url) {
            matchingDecoders.append(decoder)
        }
        return matchingDecoders
    }
}

extension DefaultMediaImageLoader {
    @concurrent
    public func loadSequence(from asset: any MediaAsset) async throws -> ImageSequence {
        let source = try await sourceFile(for: asset, priority: .userInitiated)
        defer { withExtendedLifetime(source) {} }
        try Task.checkCancellation()
        let sourceURL = source.url
        let sourceData = try Data(contentsOf: sourceURL)
        try Task.checkCancellation()
        guard let sequenceCapableDecoder = await sequenceCapableDecoder(for: sourceURL, data: sourceData) else {
            throw ImageSequenceError.unsupportedMediaSource
        }
        let frameDurations = try await sequenceCapableDecoder.frameDurations(in: sourceData)
        try Task.checkCancellation()
        return ImageSequence(identifier: asset.uniqueKey, data: sourceData, frameDurations: frameDurations)
    }
}

/// Keeps uncached download files alive until the last concurrent reader finishes.
private final class AssetSourceFile: Sendable {
    let url: URL
    private let isTemporary: Bool

    init(url: URL, isTemporary: Bool = false) {
        self.url = url
        self.isTemporary = isTemporary
    }

    deinit {
        if isTemporary { try? FileManager.default.removeItem(at: url) }
    }
}
