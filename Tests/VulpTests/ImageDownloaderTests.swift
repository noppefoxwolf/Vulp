import Foundation
import Vulp
import Testing

private final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let statusCode = Int(url.lastPathComponent),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: nil
              )
        else { return }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("image bytes".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeStubbedURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private struct OpaqueDataAssetHandle: ImageAssetHandle {
    let uniqueKey = "opaque-data"
    let fallbackImage: MediaImage? = nil
    let data: Data

    @concurrent
    func loadData(using downloader: any ImageDataDownloader) async throws -> Data {
        data
    }
}

@Test func dataAssetReturnsItsData() async throws {
    let asset = await DataImageAsset(data: TestImageData.png)
    let result = try await asset.loadData(using: DefaultImageDataDownloader())

    #expect(result == TestImageData.png)
}

@Test func assetHandleWithoutCustomDownloadReportsUnsupportedAsset() async {
    do {
        _ = try await CustomAssetHandle().loadData(using: DefaultImageDataDownloader())
        Issue.record("Expected an opaque asset to report unsupportedAsset")
    } catch let error as ImageDownloadError {
        #expect(error == .unsupportedAsset)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func customAssetHandleCanLoadWithoutBuiltInAssetType() async throws {
    let data = Data("custom source".utf8)
    let asset = OpaqueDataAssetHandle(data: data)

    #expect(try await asset.loadData(using: DefaultImageDataDownloader()) == data)
}

@Test func defaultDownloaderLoadsHTTPResponseBody() async throws {
    let body = Data("image bytes".utf8)
    let url = URL(string: "https://example.com/200")!
    let downloader = DefaultImageDataDownloader(session: makeStubbedURLSession())

    let result = try await downloader.download(from: url)

    #expect(result == body)
}

@Test func defaultDownloaderRejectsNonSuccessResponse() async {
    let url = URL(string: "https://example.com/404")!
    let downloader = DefaultImageDataDownloader(session: makeStubbedURLSession())

    do {
        _ = try await downloader.download(from: url)
        Issue.record("Expected non-success HTTP status to fail")
    } catch let error as ImageDownloadError {
        #expect(error == .unacceptableStatusCode(404))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
