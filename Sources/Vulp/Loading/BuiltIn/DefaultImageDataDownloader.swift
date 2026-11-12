import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DefaultImageDataDownloader: ImageDataDownloader {
    private let session: URLSession
    private let maximumDownloadSize: Int

    /// Creates a downloader that rejects response bodies larger than the given size.
    ///
    /// The default limit is 5 MiB. A zero limit permits only empty responses.
    public init(
        session: URLSession = .shared,
        maximumDownloadSize: Int = 5 * 1024 * 1024
    ) {
        self.session = session
        self.maximumDownloadSize = max(0, maximumDownloadSize)
    }

    @concurrent
    public func download(from url: URL) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse else {
            throw ImageDownloadError.invalidResponse
        }

        guard (200..<300).contains(response.statusCode) else {
            throw ImageDownloadError.unacceptableStatusCode(response.statusCode)
        }

        if response.expectedContentLength > Int64(maximumDownloadSize) {
            throw ImageDownloadError.exceedsMaximumSize(limit: maximumDownloadSize)
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), maximumDownloadSize))
        }

        for try await byte in bytes {
            guard data.count < maximumDownloadSize else {
                throw ImageDownloadError.exceedsMaximumSize(limit: maximumDownloadSize)
            }
            data.append(byte)
        }
        return data
    }
}
