import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DefaultImageDataDownloader: ImageDataDownloader {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    @concurrent
    public func download(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse else {
            throw ImageDownloadError.invalidResponse
        }

        guard (200..<300).contains(response.statusCode) else {
            throw ImageDownloadError.unacceptableStatusCode(response.statusCode)
        }
        return data
    }
}
