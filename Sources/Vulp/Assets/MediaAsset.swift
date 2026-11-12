import Foundation

/// A stable media source reference. Custom implementations can keep their source opaque.
public protocol MediaAsset: Sendable {
    var uniqueKey: String { get }
    var fallbackImage: MediaImage? { get }
    @concurrent
    func loadData(using downloader: any AssetDataDownloader) async throws -> Data
}

public extension MediaAsset {
    var fallbackImage: MediaImage? { nil }

    @concurrent
    func loadData(using downloader: any AssetDataDownloader) async throws -> Data {
        throw AssetDownloadError.unsupportedAsset
    }
}
