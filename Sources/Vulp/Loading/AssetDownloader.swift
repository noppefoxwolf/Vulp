import Foundation

public protocol AssetDataDownloader: Sendable {
    @concurrent
    func download(from url: URL) async throws -> Data
    /// Returns a caller-owned temporary file, or nil when file downloads are unavailable.
    @concurrent
    func downloadFile(from url: URL) async throws -> URL?
}

public enum AssetDownloadError: Error, Equatable {
    case unsupportedAsset
    case invalidResponse
    case unacceptableStatusCode(Int)
    case exceedsMaximumSize(limit: Int)
}
