import Foundation
import Vulp
import Testing

@Test func mediaImageLoaderDownloadsSourceBeforeSelectingURLDecoder() async throws {
    let videoDecoder = CountingVideoDecoder()
    let downloader = CountingAssetDownloader()
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VulpTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let dataCache = DiskAssetDataCache(directory: directory)
    let loader = DefaultMediaImageLoader(
        downloader: downloader,
        decoders: [videoDecoder],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache(),
        dataCache: dataCache
    )
    let asset = RemoteMediaAsset(
        url: URL(string: "https://example.com/clip.mp4")!,
        uniqueKey: UUID().uuidString
    )
    let request = try MediaImageRequest(asset: asset, targetSize: .zero)

    _ = try await loader.load(request)

    let decodedURLs = await videoDecoder.urls
    let cachedFileURL = await dataCache.fileURL(forKey: asset.uniqueKey)
    #expect(decodedURLs.count == 1)
    #expect(decodedURLs[0].isFileURL)
    #expect(decodedURLs[0] != asset.url)
    #expect(decodedURLs[0] == cachedFileURL)
    #expect(await downloader.callCount == 1)

    let cachedSourceDownloader = CountingAssetDownloader()
    let cachedSourceLoader = DefaultMediaImageLoader(
        downloader: cachedSourceDownloader,
        decoders: [videoDecoder],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache(),
        dataCache: dataCache
    )
    _ = try await cachedSourceLoader.load(request)

    #expect(await videoDecoder.urls == [decodedURLs[0], decodedURLs[0]])
    #expect(await cachedSourceDownloader.callCount == 0)
}

@Test func mediaImageLoaderRoutesSourcesThroughTheFirstMatchingDecoder() async throws {
    let videoDecoder = CountingVideoDecoder()
    let downloader = CountingAssetDownloader()
    let loader = DefaultMediaImageLoader(
        downloader: downloader,
        decoders: [videoDecoder],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteMediaAsset(
        url: URL(string: "https://example.com/clip.mkv")!,
        uniqueKey: UUID().uuidString
    )
    let request = try MediaImageRequest(asset: asset, targetSize: .zero)

    _ = try await loader.load(request)
    let decodedURLs = await videoDecoder.urls
    let downloadCount = await downloader.callCount

    #expect(decodedURLs.count == 1)
    #expect(decodedURLs[0].isFileURL)
    #expect(downloadCount == 1)
}

@Test func mediaImageLoaderFallsBackWhenLocalFileDecoderDeclinesSource() async throws {
    let downloader = CountingAssetDownloader()
    let loader = DefaultMediaImageLoader(
        downloader: downloader,
        decoders: [UnsupportedVideoDecoder(), ImageIOImageDecoder()],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteMediaAsset(
        url: URL(string: "https://example.com/renamed.mp4")!,
        uniqueKey: UUID().uuidString
    )
    let request = try MediaImageRequest(asset: asset, targetSize: .zero)

    let image = try await loader.load(request)
    let downloadCount = await downloader.callCount

    #expect(image.width == 1)
    #expect(downloadCount == 1)
}

@Test func videoRequestDoesNotTreatSequenceIndexAsVideoTime() async throws {
    let videoDecoder = CountingVideoDecoder()
    let loader = DefaultMediaImageLoader(
        downloader: CountingAssetDownloader(),
        decoders: [videoDecoder],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteMediaAsset(url: URL(string: "https://example.com/clip.mp4")!)
    let request = try MediaImageRequest(
        asset: asset,
        targetSize: .zero,
        decodingOptions: .frame(index: 3)
    )

    await #expect(throws: MediaImageDecodingError.videoFrameIndexUnsupported(3)) {
        try await loader.load(request)
    }

    #expect(await videoDecoder.urls.isEmpty)
}

@Test func sequenceLoadingRejectsVideoAfterDownloadingIt() async throws {
    let downloader = CountingAssetDownloader()
    let loader = DefaultMediaImageLoader(
        downloader: downloader,
        decoders: [CountingVideoDecoder()],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteMediaAsset(
        url: URL(string: "https://example.com/sequence.mp4")!,
        uniqueKey: UUID().uuidString
    )

    await #expect(throws: ImageSequenceError.unsupportedMediaSource) {
        try await loader.loadSequence(from: asset)
    }
    let downloadCount = await downloader.callCount
    #expect(downloadCount == 1)
}

private actor CountingVideoDecoder: MediaImageDecoding {
    private(set) var urls: [URL] = []

    func canDecode(url: URL) async -> Bool { true }

    func decode(
        from url: URL,
        options: ImageDecodingOptions,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        if case .frame(let index) = options {
            throw MediaImageDecodingError.videoFrameIndexUnsupported(index)
        }
        urls.append(url)
        return try await TestImageData.image()
    }
}

private struct UnsupportedVideoDecoder: MediaImageDecoding {
    func canDecode(url: URL) async -> Bool { true }

    func decode(
        from url: URL,
        options: ImageDecodingOptions,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        throw MediaImageDecodingError.unsupportedSource
    }
}
