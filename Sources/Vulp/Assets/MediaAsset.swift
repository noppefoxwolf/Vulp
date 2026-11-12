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
