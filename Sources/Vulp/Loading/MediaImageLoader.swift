import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public protocol MediaImageLoading: Sendable {
    @concurrent
    func load<Request: MediaImageRequestProtocol>(_ request: Request) async throws -> MediaImage

    @concurrent
    func load<Request: MediaImageRequestProtocol>(
        _ request: Request,
        priority: TaskPriority
    ) async throws -> MediaImage
}

public extension MediaImageLoading {
    /// Loads a request from a task created at the supplied scheduling priority.
    ///
    /// Conforming loaders may provide a more direct implementation. The default
    /// keeps existing custom loaders source-compatible.
    @concurrent
    func load<Request: MediaImageRequestProtocol>(
        _ request: Request,
        priority: TaskPriority
    ) async throws -> MediaImage {
        let task = Task(priority: priority) {
            try await load(request)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Starts a low-priority request intended to warm the image cache.
    func prefetch<Request: MediaImageRequestProtocol>(
        _ request: Request,
        priority: TaskPriority = .background
    ) -> MediaImagePrefetchTask {
        let task = Task(priority: priority) { [self] in
            do {
                _ = try await load(request, priority: priority)
            } catch is CancellationError {
                // Cancellation is expected when a prefetched item leaves the
                // collection's visible prefetch window.
            } catch {
                // A visible load can retry and report the failure to the UI.
            }
        }
        return MediaImagePrefetchTask(task: task)
    }
}

/// A cancellable handle for a cache-warming request.
public struct MediaImagePrefetchTask: Sendable {
    private let task: Task<Void, Never>

    fileprivate init(task: Task<Void, Never>) {
        self.task = task
    }

    /// Cancels this prefetch waiter. A shared load continues while other
    /// callers still need its result.
    public func cancel() {
        task.cancel()
    }

    /// Waits until the prefetch finishes or its waiter is cancelled.
    public func value() async {
        await task.value
    }
}

public typealias ImageLoading = MediaImageLoading

/// Commonly used image loaders.
public enum MediaImageLoader {
    /// A shared loader using URLSession, ImageIO, AVFoundation, image resizing, and in-memory caching.
    public static let `default`: DefaultMediaImageLoader<
        DefaultImageDataDownloader,
        MediaImageDecoderSet<ImageIOImageDecoder, AVFoundationVideoFrameDecoder>,
        ResizeImageProcessor,
        InMemoryImageCache
    > = DefaultMediaImageLoader(
        downloader: DefaultImageDataDownloader(),
        decoder: MediaImageDecoderSet(
            imageDecoder: ImageIOImageDecoder(),
            videoDecoder: AVFoundationVideoFrameDecoder()
        ),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
}

public typealias ImageLoader = MediaImageLoader

public struct DefaultMediaImageLoader<Downloader: ImageDataDownloader, Decoder: MediaImageDecoding, Processor: ImageProcessor, Cache: ImageCache>: MediaImageLoading {
    private let downloader: Downloader
    private let decoder: Decoder
    private let processor: Processor
    private let cache: Cache
    private let dataCache: any ImageDataCache
    private let fetchDeduper = ImageFetchDeduper<MediaImage>()
    private let assetDataFetchDeduper = ImageFetchDeduper<Data>()

    /// Removes all decoded images and encoded source data stored by this loader.
    public func clearCache() async {
        await cache.removeAllImages()
        await dataCache.removeAllData()
    }

    public init(
        downloader: Downloader,
        decoder: Decoder,
        processor: Processor,
        cache: Cache,
        dataCache: any ImageDataCache = DiskImageDataCache()
    ) {
        self.downloader = downloader
        self.decoder = decoder
        self.processor = processor
        self.cache = cache
        self.dataCache = dataCache
    }

    /// Compatibility initializer using the pre-media `deserializer` label.
    public init(
        downloader: Downloader,
        deserializer: Decoder,
        processor: Processor,
        cache: Cache,
        dataCache: any ImageDataCache = DiskImageDataCache()
    ) {
        self.init(downloader: downloader, decoder: deserializer, processor: processor, cache: cache, dataCache: dataCache)
    }

    @concurrent
    public func load<Request: MediaImageRequestProtocol>(_ request: Request) async throws -> MediaImage {
        try await load(request, priority: .userInitiated)
    }

    @concurrent
    public func load<Request: MediaImageRequestProtocol>(
        _ request: Request,
        priority: TaskPriority
    ) async throws -> MediaImage {
        try await load(request, process: { image in
            try await processor.process(image, for: request)
        }, priority: priority)
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
        // This caps decoder output; `request.targetSize` remains the processor's final output size.
        let maximumPixelDimension: Int? = {
            guard longestTargetEdge.isFinite,
                  longestTargetEdge > 0,
                  longestTargetEdge < CGFloat(Int.max)
            else { return nil }
            return Int(longestTargetEdge.rounded(.up))
        }()

        let asset = request.assetHandle
        let image: MediaImage
        let usedFallback: Bool
        do {
            try Task.checkCancellation()
            switch MediaSourceResolver.resolution(for: asset) {
            case .imageData:
                image = try await decodeImageData(
                    for: asset,
                    request: request,
                    maximumPixelDimension: maximumPixelDimension,
                    priority: priority
                )
            case .videoURL(let url):
                image = try await decodeVideoOrRecheck(
                    url,
                    asset: asset,
                    request: request,
                    maximumPixelDimension: maximumPixelDimension,
                    priority: priority
                )
            case .probeVideoURL(let url):
                do {
                    image = try await decodeVideoFrame(
                        from: url,
                        request: request,
                        maximumPixelDimension: maximumPixelDimension
                    )
                } catch MediaImageDecodingError.unsupportedSource {
                    image = try await decodeImageData(
                        for: asset,
                        request: request,
                        maximumPixelDimension: maximumPixelDimension,
                        priority: priority
                    )
                }
            }
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

    private func decodeVideoOrRecheck<Request: MediaImageRequestProtocol>(
        _ url: URL,
        asset: any MediaAsset,
        request: Request,
        maximumPixelDimension: Int?,
        priority: TaskPriority
    ) async throws -> MediaImage {
        do {
            return try await decodeVideoFrame(
                from: url,
                request: request,
                maximumPixelDimension: maximumPixelDimension
            )
        } catch MediaImageDecodingError.unsupportedSource {
            return try await decodeImageData(
                for: asset,
                request: request,
                maximumPixelDimension: maximumPixelDimension,
                priority: priority
            )
        }
    }

    private func decodeVideoFrame<Request: MediaImageRequestProtocol>(
        from url: URL,
        request: Request,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        if case .frame(let index) = request.decodingOptions {
            throw MediaImageDecodingError.videoFrameIndexUnsupported(index)
        }
        return try await decoder.decodeVideoFrame(
            from: url,
            at: 0,
            maximumPixelDimension: maximumPixelDimension
        )
    }

    private func decodeImageData<Request: MediaImageRequestProtocol>(
        for asset: any MediaAsset,
        request: Request,
        maximumPixelDimension: Int?,
        priority: TaskPriority
    ) async throws -> MediaImage {
        let data = try await data(for: asset, priority: priority)
        try Task.checkCancellation()
        return try await decoder.deserialize(
            data,
            options: request.decodingOptions,
            maximumPixelDimension: maximumPixelDimension
        )
    }

    private func data(
        for asset: any MediaAsset,
        priority: TaskPriority = .userInitiated
    ) async throws -> Data {
        if let cached = await dataCache.data(forKey: asset.uniqueKey) {
            return cached
        }
        return try await assetDataFetchDeduper.load(forKey: asset.uniqueKey, priority: priority) { [self] in
            let downloaded = try await asset.loadData(using: downloader)
            await dataCache.insert(downloaded, forKey: asset.uniqueKey)
            return downloaded
        }
    }
}

extension DefaultMediaImageLoader: MediaImageSequenceLoading where Decoder: MediaImageSequenceDecoding {
    @concurrent
    public func loadSequence(from asset: any MediaAsset) async throws -> ImageSequence {
        switch MediaSourceResolver.resolution(for: asset) {
        case .videoURL:
            throw ImageSequenceError.unsupportedMediaSource
        case .probeVideoURL(let url):
            do {
                _ = try await decoder.decodeVideoFrame(from: url, at: 0, maximumPixelDimension: 1)
                throw ImageSequenceError.unsupportedMediaSource
            } catch MediaImageDecodingError.unsupportedSource {
                break
            }
        case .imageData:
            break
        }
        let data = try await data(for: asset)
        try Task.checkCancellation()
        let frameDurations = try await decoder.frameDurations(in: data)
        try Task.checkCancellation()
        return ImageSequence(identifier: asset.uniqueKey, data: data, frameDurations: frameDurations)
    }
}

public typealias DefaultImageLoader<
    Downloader: ImageDataDownloader,
    Decoder: MediaImageDecoding,
    Processor: ImageProcessor,
    Cache: ImageCache
> =
    DefaultMediaImageLoader<Downloader, Decoder, Processor, Cache>
