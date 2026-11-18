import Foundation
import Synchronization

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DefaultAssetDataDownloader: AssetDataDownloader {
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
        try validateHTTPResponse(response)

        if response.expectedContentLength > Int64(maximumDownloadSize) {
            throw AssetDownloadError.exceedsMaximumSize(limit: maximumDownloadSize)
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), maximumDownloadSize))
        }

        for try await byte in bytes {
            guard data.count < maximumDownloadSize else {
                throw AssetDownloadError.exceedsMaximumSize(limit: maximumDownloadSize)
            }
            data.append(byte)
        }
        return data
    }

    /// Returns a caller-owned download file for the disk-backed image loader.
    @concurrent
    public func downloadFile(from url: URL) async throws -> URL? {
        let limit = DownloadFileSizeLimit(maximumSize: maximumDownloadSize)
        let (fileURL, response): (URL, URLResponse)
        do {
            (fileURL, response) = try await session.download(from: url, delegate: limit)
        } catch {
            if limit.exceeded { throw AssetDownloadError.exceedsMaximumSize(limit: maximumDownloadSize) }
            throw error
        }

        do {
            try validateHTTPResponse(response)
            let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard !limit.exceeded, size <= maximumDownloadSize,
                  response.expectedContentLength <= Int64(maximumDownloadSize) else {
                throw AssetDownloadError.exceedsMaximumSize(limit: maximumDownloadSize)
            }
            return fileURL
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
    }
}

private final class DownloadFileSizeLimit: NSObject, URLSessionDownloadDelegate {
    private let maximumSize: Int
    private let exceededLimit = Mutex(false)

    init(maximumSize: Int) {
        self.maximumSize = maximumSize
    }

    var exceeded: Bool {
        exceededLimit.withLock { $0 }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let response = downloadTask.response,
              (try? validateHTTPResponse(response)) != nil,
              totalBytesWritten > maximumSize || totalBytesExpectedToWrite > maximumSize else { return }
        exceededLimit.withLock { $0 = true }
        downloadTask.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}

// URLSession exposes HTTP metadata through its general URLResponse type.
private func validateHTTPResponse(_ response: URLResponse) throws {
    guard let response = response as? HTTPURLResponse else {
        throw AssetDownloadError.invalidResponse
    }
    guard (200..<300).contains(response.statusCode) else {
        throw AssetDownloadError.unacceptableStatusCode(response.statusCode)
    }
}
