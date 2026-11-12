import Foundation
import Vulp
import Testing

struct CustomAsset: MediaAsset {
    let uniqueKey = "custom"
    let fallbackImage: MediaImage? = nil
}

@Test func remoteAssetUsesURLAsItsDefaultKey() {
    let url = URL(string: "https://example.com/image.png")!
    let asset = RemoteMediaAsset(url: url)

    #expect(asset.uniqueKey == url.absoluteString)
    #expect(asset.fallbackImage == nil)
}

@Test func assetDoesNotRequireABuiltInSourceEnum() {
    let asset: any MediaAsset = CustomAsset()

    #expect(asset.uniqueKey == "custom")
}

@Test func assetAcceptsExplicitKeyAndFallback() async throws {
    let fallback = try await TestImageData.image()
    let asset = DataMediaAsset(
        data: TestImageData.png,
        uniqueKey: "avatar",
        fallbackImage: fallback
    )

    #expect(asset.uniqueKey == "avatar")
    #expect(asset.fallbackImage === fallback)
}

@Test func requestBuildsCacheIdentifierFromInputs() throws {
    let asset = RemoteMediaAsset(
        url: URL(string: "https://example.com/a.png")!,
        uniqueKey: "avatar"
    )
    let request = try ImageLoadRequest(
        asset: asset,
        targetSize: CGSize(width: 40, height: 30)
    )

    #expect(request.cacheIdentifier == "avatar|64.0x48.0")
}

@Test func requestRejectsNegativeDimensions() {
    let asset = DataMediaAsset(data: TestImageData.png, uniqueKey: "fixture")

    #expect(throws: ImageLoadRequestError.invalidTargetSize) {
        try ImageLoadRequest(
            asset: asset,
            targetSize: CGSize(width: -1, height: 10)
        )
    }
}
