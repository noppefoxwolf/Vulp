import Foundation
import Vulp
import Testing

private actor StubHTTPImageDataTransport: HTTPImageDataTransport {
    private let response: ImageHTTPResponse
    private(set) var requestedURL: URL?

    init(response: ImageHTTPResponse) {
        self.response = response
    }

    func data(from url: URL) async throws -> ImageHTTPResponse {
        requestedURL = url
        return response
    }
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
    let asset = DataImageAsset(data: TestImageData.png)
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

@Test func defaultDownloaderUsesInjectedHTTPTransport() async throws {
    let body = Data("image bytes".utf8)
    let url = URL(string: "https://example.com/image")!
    let transport = StubHTTPImageDataTransport(response: ImageHTTPResponse(data: body, statusCode: 200))
    let downloader = DefaultImageDataDownloader(transport: transport)
    let asset = RemoteImageAsset(url: url, uniqueKey: "remote")

    let result = try await asset.loadData(using: downloader)

    #expect(result == body)
    #expect(await transport.requestedURL == url)
}

@Test func defaultDownloaderRejectsNonSuccessResponse() async {
    let url = URL(string: "https://example.com/missing")!
    let transport = StubHTTPImageDataTransport(response: ImageHTTPResponse(data: Data(), statusCode: 404))
    let downloader = DefaultImageDataDownloader(transport: transport)
    let asset = RemoteImageAsset(url: url, uniqueKey: "missing")

    do {
        _ = try await asset.loadData(using: downloader)
        Issue.record("Expected non-success HTTP status to fail")
    } catch let error as ImageDownloadError {
        #expect(error == .unacceptableStatusCode(404))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
