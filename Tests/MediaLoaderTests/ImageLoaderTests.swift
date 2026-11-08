import Foundation
import MediaLoader
import Testing

@Test func imageLoaderCachesAndReturnsProcessedImage() async throws {
    let cache = InMemoryImageCache()
    let loader = DefaultImageLoader(
        downloader: DefaultImageDataDownloader(),
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: cache
    )
    let asset = DataImageAsset(data: TestImageData.png, uniqueKey: "fixture")
    let request = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: CGSize(width: 6, height: 4)
    )

    let first = try await loader.load(request)
    let second = try await loader.load(request)

    #expect(first.pixelWidth == 8)
    #expect(first.pixelHeight == 5)
    #expect(second === first)
}

@Test func imageLoaderDeduplicatesConcurrentRequests() async throws {
    let downloader = CountingDownloader()
    let loader = DefaultImageLoader(
        downloader: downloader,
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteImageAsset(
        url: URL(string: "https://example.com/shared-flight.png")!,
        uniqueKey: "shared-flight-\(UUID().uuidString)"
    )
    let request = try ImageLoadRequest(assetHandle: asset, targetSize: .zero)

    async let first: Void = { _ = try await loader.load(request) }()
    async let second: Void = { _ = try await loader.load(request) }()
    _ = try await (first, second)

    #expect(await downloader.callCount == 1)
}

@Test func prefetchLoadsImageIntoSharedCache() async throws {
    let downloader = CountingDownloader()
    let loader = DefaultImageLoader(
        downloader: downloader,
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteImageAsset(
        url: URL(string: "https://example.com/prefetch.png")!,
        uniqueKey: "prefetch-\(UUID().uuidString)"
    )
    let request = try ImageLoadRequest(assetHandle: asset, targetSize: .zero)

    let prefetch = loader.prefetch(request)
    await prefetch.value()
    _ = try await loader.load(request)

    #expect(await downloader.callCount == 1)
}

@Test func imageLoadAcceptsExplicitTaskPriority() async throws {
    let downloader = CountingDownloader()
    let loader = DefaultImageLoader(
        downloader: downloader,
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteImageAsset(
        url: URL(string: "https://example.com/priority.png")!,
        uniqueKey: "priority-\(UUID().uuidString)"
    )
    let request = try ImageLoadRequest(assetHandle: asset, targetSize: .zero)

    _ = try await loader.load(request, priority: .background)

    #expect(await downloader.lastPriority == .background)
}

@Test func cancellingPrefetchWaiterDoesNotCancelSharedLoad() async throws {
    let downloader = CountingDownloader(delay: .milliseconds(250))
    let loader = DefaultImageLoader(
        downloader: downloader,
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteImageAsset(
        url: URL(string: "https://example.com/prefetch-cancel.png")!,
        uniqueKey: "prefetch-cancel-\(UUID().uuidString)"
    )
    let request = try ImageLoadRequest(assetHandle: asset, targetSize: .zero)
    let prefetch = loader.prefetch(request)
    let visibleLoad = Task { try await loader.load(request) }
    try await Task.sleep(for: .milliseconds(30))

    prefetch.cancel()
    await prefetch.value()
    _ = try await visibleLoad.value

    #expect(await downloader.callCount == 1)
}

@Test func cancellingOnlyPrefetchCancelsUnderlyingLoadAndAllowsRetry() async throws {
    let downloader = CountingDownloader(delay: .seconds(2))
    let loader = DefaultImageLoader(
        downloader: downloader,
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteImageAsset(
        url: URL(string: "https://example.com/prefetch-only-cancel.png")!,
        uniqueKey: "prefetch-only-cancel-\(UUID().uuidString)"
    )
    let request = try ImageLoadRequest(assetHandle: asset, targetSize: .zero)
    let prefetch = loader.prefetch(request)
    try await Task.sleep(for: .milliseconds(50))

    prefetch.cancel()
    await prefetch.value()
    try await Task.sleep(for: .milliseconds(20))

    #expect(await downloader.cancellationCount == 1)
    _ = try await loader.load(request)
    #expect(await downloader.callCount == 2)
}

@Test func imageLoaderDeduplicatesConcurrentAssetDownloadsAcrossRequests() async throws {
    let downloader = CountingDownloader(delay: .milliseconds(250))
    let loader = DefaultImageLoader(
        downloader: downloader,
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteImageAsset(
        url: URL(string: "https://example.com/shared-asset.png")!,
        uniqueKey: "shared-asset-\(UUID().uuidString)"
    )
    let smallRequest = try ImageLoadRequest(assetHandle: asset, targetSize: CGSize(width: 8, height: 8))
    let largeRequest = try ImageLoadRequest(assetHandle: asset, targetSize: CGSize(width: 16, height: 16))

    async let small: Void = { _ = try await loader.load(smallRequest) }()
    async let large: Void = { _ = try await loader.load(largeRequest) }()
    _ = try await (small, large)

    #expect(await downloader.callCount == 1)
}

@Test func imageLoaderUsesFallbackWithoutCachingIt() async throws {
    let fallback = try await TestImageData.image()
    let cache = LRUImageCache()
    let loader = DefaultImageLoader(
        downloader: FailingDownloader(),
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: cache
    )
    let asset = RemoteImageAsset(
        url: URL(string: "https://example.com/missing.png")!,
        uniqueKey: "with-fallback",
        fallbackImage: fallback
    )
    let request = try ImageLoadRequest(assetHandle: asset, targetSize: .zero)

    let result = try await loader.load(request)

    #expect(result === fallback)
    #expect(await cache.image(forKey: request.cacheIdentifier) == nil)
}

@Test func cancellingOneWaiterDoesNotCancelTheSharedLoad() async throws {
    let downloader = CountingDownloader(delay: .milliseconds(250))
    let loader = DefaultImageLoader(
        downloader: downloader,
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteImageAsset(
        url: URL(string: "https://example.com/cancel-waiter.png")!,
        uniqueKey: "cancel-waiter-\(UUID().uuidString)"
    )
    let request = try ImageLoadRequest(assetHandle: asset, targetSize: .zero)
    let leader = Task { _ = try await loader.load(request) }
    try await Task.sleep(for: .milliseconds(30))
    let waiter = Task { _ = try await loader.load(request) }
    try await Task.sleep(for: .milliseconds(20))

    waiter.cancel()
    do {
        _ = try await waiter.value
        Issue.record("Expected the cancelled waiter to throw CancellationError")
    } catch is CancellationError {
        #expect(Bool(true))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    _ = try await leader.value
    #expect(await downloader.callCount == 1)
}
