import Foundation
import Vulp
import Testing

@Test func mediaImageLoaderDecodesRemoteVideoURLWithoutDownloadingWholeSource() async throws {
    let videoDecoder = CountingVideoDecoder()
    let downloader = CountingDownloader()
    let loader = DefaultMediaImageLoader(
        downloader: downloader,
        decoders: [videoDecoder],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteMediaAsset(url: URL(string: "https://example.com/clip.mp4")!)
    let request = try MediaImageRequest(assetHandle: asset, targetSize: .zero)

    _ = try await loader.load(request)

    #expect(await videoDecoder.urls == [asset.url])
    #expect(await downloader.callCount == 0)
}

@Test func mediaImageLoaderRoutesSourcesThroughTheFirstMatchingDecoder() async throws {
    let videoDecoder = CountingVideoDecoder()
    let downloader = CountingDownloader()
    let loader = DefaultMediaImageLoader(
        downloader: downloader,
        decoders: [videoDecoder],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteMediaAsset(url: URL(string: "https://example.com/clip.mkv")!)
    let request = try MediaImageRequest(assetHandle: asset, targetSize: .zero)

    _ = try await loader.load(request)
    let decodedURLs = await videoDecoder.urls
    let downloadCount = await downloader.callCount

    #expect(decodedURLs == [asset.url])
    #expect(downloadCount == 0)
}

@Test func mediaImageLoaderLetsDecoderCapabilityOverrideMediaTypeHint() async throws {
    let videoDecoder = CountingVideoDecoder()
    let loader = DefaultMediaImageLoader(
        downloader: CountingDownloader(),
        decoders: [videoDecoder],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteMediaAsset(
        url: URL(string: "https://example.com/clip.mp4")!,
        mediaTypeHint: .image
    )
    let request = try MediaImageRequest(assetHandle: asset, targetSize: .zero)

    _ = try await loader.load(request)

    #expect(await videoDecoder.urls == [asset.url])
}

@Test func mediaImageLoaderFallsBackToImageDataWhenDirectURLDecoderDeclinesSource() async throws {
    let downloader = CountingDownloader()
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
    let request = try MediaImageRequest(assetHandle: asset, targetSize: .zero)

    let image = try await loader.load(request)
    let downloadCount = await downloader.callCount

    #expect(image.width == 1)
    #expect(downloadCount == 1)
}

@Test func videoRequestDoesNotTreatSequenceIndexAsVideoTime() async throws {
    let videoDecoder = CountingVideoDecoder()
    let loader = DefaultMediaImageLoader(
        downloader: CountingDownloader(),
        decoders: [videoDecoder],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteMediaAsset(url: URL(string: "https://example.com/clip.mp4")!)
    let request = try MediaImageRequest(
        assetHandle: asset,
        targetSize: .zero,
        decodingOptions: .frame(index: 3)
    )

    await #expect(throws: MediaImageDecodingError.videoFrameIndexUnsupported(3)) {
        try await loader.load(request)
    }

    #expect(await videoDecoder.urls.isEmpty)
}

@Test func sequenceLoadingRejectsKnownVideoBeforeDownloadingIt() async throws {
    let downloader = CountingDownloader()
    let loader = DefaultMediaImageLoader(
        downloader: downloader,
        decoders: [CountingVideoDecoder()],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteMediaAsset(url: URL(string: "https://example.com/sequence.mp4")!)

    await #expect(throws: ImageSequenceError.unsupportedMediaSource) {
        try await loader.loadSequence(from: asset)
    }
    let downloadCount = await downloader.callCount
    #expect(downloadCount == 0)
}

private actor CountingVideoDecoder: VideoFrameDecoding {
    private(set) var urls: [URL] = []

    func canDecode(data: Data) async -> Bool { false }
    func canDecode(url: URL) async -> Bool { true }

    func decodeFrame(
        from url: URL,
        at time: TimeInterval,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        urls.append(url)
        return try await TestImageData.image()
    }
}

private struct UnsupportedVideoDecoder: VideoFrameDecoding {
    func canDecode(data: Data) async -> Bool { false }
    func canDecode(url: URL) async -> Bool { true }

    func decodeFrame(
        from url: URL,
        at time: TimeInterval,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        throw MediaImageDecodingError.unsupportedSource
    }
}
