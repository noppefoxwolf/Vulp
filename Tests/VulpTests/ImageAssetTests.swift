import Foundation
import Vulp
import Testing

struct CustomAssetHandle: ImageAssetHandle {
    let uniqueKey = "custom"
    let fallbackImage: MediaImage? = nil
}

@Test func remoteAssetUsesURLAsItsDefaultKey() {
    let url = URL(string: "https://example.com/image.png")!
    let asset = RemoteImageAsset(url: url)

    #expect(asset.uniqueKey == url.absoluteString)
    #expect(asset.fallbackImage == nil)
}

@Test func assetHandleDoesNotRequireABuiltInSourceEnum() {
    let asset: any ImageAssetHandle = CustomAssetHandle()

    #expect(asset.uniqueKey == "custom")
}

@Test func assetAcceptsExplicitKeyAndFallback() async throws {
    let fallback = try await TestImageData.image()
    let asset = DataImageAsset(
        data: TestImageData.png,
        uniqueKey: "avatar",
        fallbackImage: fallback
    )

    #expect(asset.uniqueKey == "avatar")
    #expect(asset.fallbackImage === fallback)
}

@Test func requestBuildsCacheIdentifierFromInputs() throws {
    let asset = RemoteImageAsset(
        url: URL(string: "https://example.com/a.png")!,
        uniqueKey: "avatar"
    )
    let request = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: CGSize(width: 40, height: 30)
    )

    #expect(request.cacheIdentifier == "avatar|64.0x48.0|original|resize:fit")
}

@Test func requestRejectsNegativeDimensions() {
    let asset = DataImageAsset(data: TestImageData.png, uniqueKey: "fixture")

    #expect(throws: ImageLoadRequestError.invalidTargetSize) {
        try ImageLoadRequest(
            assetHandle: asset,
            targetSize: CGSize(width: -1, height: 10)
        )
    }
}
