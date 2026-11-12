import Foundation

public protocol ImageDataDownloader: Sendable {
    @concurrent
    func download(from url: URL) async throws -> Data
}

public enum ImageDownloadError: Error, Equatable {
    case unsupportedAsset
    case invalidResponse
    case unacceptableStatusCode(Int)
}
