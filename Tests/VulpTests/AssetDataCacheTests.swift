import Foundation
import Vulp
import Testing

@Test func diskAssetDataCachePersistsDataAcrossInstances() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VulpTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = TestImageData.png

    let firstCache = DiskAssetDataCache(directory: directory)
    let insertedURL = await firstCache.insert(data, forKey: "https://example.com/image.png")
    #expect(insertedURL?.isFileURL == true)

    let secondCache = DiskAssetDataCache(directory: directory)
    let cachedURL = await secondCache.fileURL(forKey: "https://example.com/image.png")
    #expect(cachedURL == insertedURL)
    #expect(try cachedURL.map { try Data(contentsOf: $0) } == data)
}

@Test func imageLoaderReadsAssetDataFromDiskCacheBeforeDownloading() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VulpTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let dataCache = DiskAssetDataCache(directory: directory)
    let firstDownloader = CountingAssetDownloader()
    let asset = RemoteMediaAsset(
        url: URL(string: "https://example.com/disk-cached-source.png")!,
        uniqueKey: "disk-cached-source"
    )
    let request = try MediaImageRequest(asset: asset, targetSize: .zero)
    let firstLoader = DefaultMediaImageLoader(
        downloader: firstDownloader,
        decoders: [ImageIOImageDecoder()],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache(),
        dataCache: dataCache
    )
    _ = try await firstLoader.load(request)

    let secondDownloader = CountingAssetDownloader()
    let secondLoader = DefaultMediaImageLoader(
        downloader: secondDownloader,
        decoders: [ImageIOImageDecoder()],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache(),
        dataCache: DiskAssetDataCache(directory: directory)
    )
    _ = try await secondLoader.load(request)

    #expect(await firstDownloader.callCount == 1)
    #expect(await secondDownloader.callCount == 0)
}
