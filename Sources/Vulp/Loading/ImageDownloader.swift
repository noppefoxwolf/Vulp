import Foundation

public protocol ImageDataDownloader: Sendable {
    @concurrent
    func download(from url: URL) async throws -> Data
}

public struct ImageHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol HTTPImageDataTransport: Sendable {
    func data(from url: URL) async throws -> ImageHTTPResponse
}

public enum ImageDownloadError: Error, Equatable {
    case unsupportedAsset
    case invalidResponse
    case unacceptableStatusCode(Int)
}
