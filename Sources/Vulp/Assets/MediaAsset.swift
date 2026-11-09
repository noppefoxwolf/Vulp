import Foundation

/// A stable media source reference. Custom implementations can keep their source opaque.
public protocol MediaAsset: Sendable {
    var uniqueKey: String { get }
    var fallbackImage: MediaImage? { get }
    /// A URL that a format-specific decoder can consume directly, without downloading the full source.
    var directURL: URL? { get }
    @concurrent
    func loadData(using downloader: any ImageDataDownloader) async throws -> Data
}

public typealias ImageAssetHandle = MediaAsset

public extension MediaAsset {
    var fallbackImage: MediaImage? { nil }
    var directURL: URL? { nil }

    @concurrent
    func loadData(using downloader: any ImageDataDownloader) async throws -> Data {
        throw ImageDownloadError.unsupportedAsset
    }
}

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

/// An image asset backed by already encoded image data.
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
    public func loadData(using downloader: any ImageDataDownloader) async throws -> Data {
        data
    }
}

/// Backward-compatible names retained while the package is pre-major.
public typealias RemoteImageAsset = RemoteMediaAsset
public typealias FileImageAsset = FileMediaAsset
public typealias DataImageAsset = DataMediaAsset
