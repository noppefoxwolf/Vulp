import Foundation

/// A media asset backed by a remote URL.
public struct RemoteMediaAsset: MediaAsset {
    public let url: URL
    public let uniqueKey: String
    public let fallbackImage: MediaImage?

    public init(
        url: URL,
        uniqueKey: String? = nil,
        fallbackImage: MediaImage? = nil
    ) {
        self.url = url
        self.uniqueKey = uniqueKey ?? url.absoluteString
        self.fallbackImage = fallbackImage
    }

    public var directURL: URL? { url }

    @concurrent
    public func loadData(using downloader: any ImageDataDownloader) async throws -> Data {
        try await downloader.download(from: url)
    }
}
