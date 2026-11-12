import Foundation

public protocol AssetDataDownloader: Sendable {
    @concurrent
    func download(from url: URL) async throws -> Data
}

public enum AssetDownloadError: Error, Equatable {
    case unsupportedAsset
    case invalidResponse
    case unacceptableStatusCode(Int)
    case exceedsMaximumSize(limit: Int)
}
