import Foundation
import Vulp
import Testing

@Test func diskImageDataCachePersistsDataAcrossInstances() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VulpTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = TestImageData.png

    let firstCache = DiskImageDataCache(directory: directory)
    await firstCache.insert(data, forKey: "https://example.com/image.png")

    let secondCache = DiskImageDataCache(directory: directory)
    #expect(await secondCache.data(forKey: "https://example.com/image.png") == data)
}

@Test func imageLoaderReadsOriginalDataFromDiskCacheBeforeDownloading() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VulpTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let dataCache = DiskImageDataCache(directory: directory)
    let firstDownloader = CountingDownloader()
    let asset = RemoteImageAsset(
        url: URL(string: "https://example.com/disk-cached-source.png")!,
        uniqueKey: "disk-cached-source"
    )
    let request = try ImageLoadRequest(assetHandle: asset, targetSize: .zero)
    let firstLoader = DefaultImageLoader(
        downloader: firstDownloader,
        decoder: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache(),
        dataCache: dataCache
    )
    _ = try await firstLoader.load(request)

    let secondDownloader = CountingDownloader()
    let secondLoader = DefaultImageLoader(
        downloader: secondDownloader,
        decoder: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache(),
        dataCache: DiskImageDataCache(directory: directory)
    )
    _ = try await secondLoader.load(request)

    #expect(await firstDownloader.callCount == 1)
    #expect(await secondDownloader.callCount == 0)
}
