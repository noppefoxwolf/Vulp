import Foundation

/// An image asset backed by a local file URL.
public struct FileMediaAsset: MediaAsset {
    public let url: URL
    public let uniqueKey: String
    public let fallbackImage: MediaImage?

    public var directURL: URL? { url }

    public init(
        url: URL,
        uniqueKey: String? = nil,
        fallbackImage: MediaImage? = nil
    ) {
        self.url = url
        self.uniqueKey = uniqueKey ?? url.standardizedFileURL.absoluteString
        self.fallbackImage = fallbackImage
    }

    @concurrent
    public func loadData(using downloader: any ImageDataDownloader) async throws -> Data {
        try Data(contentsOf: url)
    }
}
