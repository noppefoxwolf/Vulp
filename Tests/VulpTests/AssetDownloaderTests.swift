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
        client?.urlProtocol(self, didLoad: Data("asset bytes".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeStubbedURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private struct OpaqueDataAsset: MediaAsset {
    let uniqueKey = "opaque-data"
    let fallbackImage: MediaImage? = nil
    let data: Data

    @concurrent
    func loadData(using downloader: any AssetDataDownloader) async throws -> Data {
        data
    }
}

@Test func dataAssetReturnsItsData() async throws {
    let asset = await DataMediaAsset(data: TestImageData.png)
    let result = try await asset.loadData(using: DefaultAssetDataDownloader())

    #expect(result == TestImageData.png)
}

@Test func assetWithoutCustomDownloadReportsUnsupportedAsset() async {
    do {
        _ = try await CustomAsset().loadData(using: DefaultAssetDataDownloader())
        Issue.record("Expected an opaque asset to report unsupportedAsset")
    } catch let error as AssetDownloadError {
        #expect(error == .unsupportedAsset)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func customAssetCanLoadWithoutBuiltInAssetType() async throws {
    let data = Data("custom source".utf8)
    let asset = OpaqueDataAsset(data: data)

    #expect(try await asset.loadData(using: DefaultAssetDataDownloader()) == data)
}

@Test func defaultAssetDataDownloaderLoadsHTTPResponseBody() async throws {
    let body = Data("asset bytes".utf8)
    let url = URL(string: "https://example.com/200")!
    let downloader = DefaultAssetDataDownloader(session: makeStubbedURLSession())

    let result = try await downloader.download(from: url)

    #expect(result == body)
}

@Test func defaultAssetDataDownloaderRejectsNonSuccessResponse() async {
    let url = URL(string: "https://example.com/404")!
    let downloader = DefaultAssetDataDownloader(session: makeStubbedURLSession())

    do {
        _ = try await downloader.download(from: url)
        Issue.record("Expected non-success HTTP status to fail")
    } catch let error as AssetDownloadError {
        #expect(error == .unacceptableStatusCode(404))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
