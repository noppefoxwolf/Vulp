import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct URLSessionHTTPImageDataTransport: HTTPImageDataTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(from url: URL) async throws -> ImageHTTPResponse {
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse else {
            throw ImageDownloadError.invalidResponse
        }
        return ImageHTTPResponse(data: data, statusCode: response.statusCode)
    }
}

public struct DefaultImageDataDownloader: ImageDataDownloader {
    private let transport: any HTTPImageDataTransport

    public init(session: URLSession = .shared) {
        self.transport = URLSessionHTTPImageDataTransport(session: session)
    }

    public init(transport: any HTTPImageDataTransport) {
        self.transport = transport
    }

    @concurrent
    public func download(from url: URL) async throws -> Data {
        let response = try await transport.data(from: url)
        guard (200..<300).contains(response.statusCode) else {
            throw ImageDownloadError.unacceptableStatusCode(response.statusCode)
        }
        return response.data
    }
}
