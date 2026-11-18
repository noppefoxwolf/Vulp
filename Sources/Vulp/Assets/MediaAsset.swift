import Foundation

/// A stable media source reference. Custom implementations can keep their source opaque.
public protocol MediaAsset: Sendable {
    var uniqueKey: String { get }
    var fallbackImage: MediaImage? { get }
    /// Returns a caller-owned temporary file, or nil to use the data loading path.
    @concurrent
    func loadFile(using downloader: any AssetDataDownloader) async throws -> URL?
    @concurrent
    func loadData(using downloader: any AssetDataDownloader) async throws -> Data
}

public extension MediaAsset {
    var fallbackImage: MediaImage? { nil }

    @concurrent
    func loadFile(using downloader: any AssetDataDownloader) async throws -> URL? { nil }

    @concurrent
    func loadData(using downloader: any AssetDataDownloader) async throws -> Data {
        throw AssetDownloadError.unsupportedAsset
    }
}
