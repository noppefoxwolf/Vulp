import Foundation

/// A media asset backed by already encoded source data.
public struct DataMediaAsset: MediaAsset {
    public let data: Data
    public let uniqueKey: String
    public let fallbackImage: MediaImage?
    /// Creates an asset and derives a stable cache key from its encoded data.
    @concurrent
    public init(data: Data, fallbackImage: MediaImage? = nil) async {
        self.data = data
        self.fallbackImage = fallbackImage
        let hash = data.reduce(into: UInt64(14695981039346656037)) { hash, byte in
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        self.uniqueKey = "data:\(data.count):\(hash)"
    }

    /// Creates an asset with a caller-provided stable cache key.
    public init(data: Data, uniqueKey: String, fallbackImage: MediaImage? = nil) {
        self.data = data
        self.uniqueKey = uniqueKey
        self.fallbackImage = fallbackImage
    }

    @concurrent
    public func loadData(using downloader: any AssetDataDownloader) async throws -> Data {
        data
    }
}
