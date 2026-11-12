import Foundation

/// A media asset backed by a local file URL.
public struct FileMediaAsset: MediaAsset {
    public let url: URL
    public let uniqueKey: String
    public let fallbackImage: MediaImage?

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
    public func loadData(using downloader: any AssetDataDownloader) async throws -> Data {
        try Data(contentsOf: url)
    }
}
