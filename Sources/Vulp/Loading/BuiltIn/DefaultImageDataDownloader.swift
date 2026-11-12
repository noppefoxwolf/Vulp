import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DefaultImageDataDownloader: ImageDataDownloader {
    private enum Transport: Sendable {
        case urlSession(URLSession)
        case custom(any HTTPImageDataTransport)
    }

    private let transport: Transport

    public init(session: URLSession = .shared) {
        self.transport = .urlSession(session)
    }

    public init(transport: any HTTPImageDataTransport) {
        self.transport = .custom(transport)
    }

    @concurrent
    public func download(from url: URL) async throws -> Data {
        let response: ImageHTTPResponse
        switch transport {
        case .urlSession(let session):
            let (data, urlResponse) = try await session.data(from: url)
            guard let urlResponse = urlResponse as? HTTPURLResponse else {
                throw ImageDownloadError.invalidResponse
            }
            response = ImageHTTPResponse(data: data, statusCode: urlResponse.statusCode)
        case .custom(let transport):
            response = try await transport.data(from: url)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw ImageDownloadError.unacceptableStatusCode(response.statusCode)
        }
        return response.data
    }
}
