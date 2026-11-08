import MediaLoader
import MediaLoaderUI
import SwiftUI
import Testing

private struct TestImageLoader: ImageLoading {
    @concurrent
    func load<Request: ImageRequest>(_ request: Request) async throws -> MediaImage {
        let isolation: (any Actor)? = #isolation
        if let isolation {
            throw TestImageLoaderError.unexpectedActorIsolation(String(describing: isolation))
        }

        let data = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
        )!
        return try await ImageIOImageDeserializer().deserialize(data)
    }
}

private enum TestImageLoaderError: Error {
    case unexpectedActorIsolation(String)
}

@Test @MainActor func umbrellaProductExposesSwiftUIAsyncImage() throws {
    let request = try ImageLoadRequest(
        assetHandle: DataImageAsset(data: Data(), uniqueKey: "swiftui-view"),
        targetSize: .zero
    )

    let view = MediaLoaderUI.AsyncImage(request: request, loader: TestImageLoader()) {
        ProgressView()
    }

    _ = view
}

@Test @MainActor func imageLoaderViewBuildsARequestFromViewSizeAndScale() {
    let view = MediaLoaderUI.AsyncImage(
        loader: TestImageLoader(),
        request: { targetSize, scale in
            try ImageLoadRequest(
                assetHandle: DataImageAsset(data: Data(), uniqueKey: "swiftui-builder"),
                targetSize: targetSize ?? .zero,
                scale: scale
            )
        }
    ) {
        ProgressView()
    }

    _ = view
}

@Test @MainActor func imageLoaderViewAcceptsSequenceAssetAndLoader() {
    let loader = DefaultImageLoader(
        downloader: DefaultImageDataDownloader(),
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = DataImageAsset(data: Data([0]), uniqueKey: "sequence-view")
    let view = MediaLoaderUI.AsyncImage(
        asset: asset,
        loader: loader,
        targetSize: CGSize(width: 16, height: 16),
        levelOfIntegrity: 0.9
    ) {
        ProgressView()
    }

    _ = view
}

@Test @MainActor func imageLoaderCanRunFromMainActorWithoutInheritingItsIsolation() async throws {
    let request = try ImageLoadRequest(
        assetHandle: DataImageAsset(data: Data(), uniqueKey: "main-actor-test"),
        targetSize: .zero
    )
    let image = try await TestImageLoader().load(request)

    #expect(image.pixelWidth == 1)
    #expect(image.pixelHeight == 1)
}

@Test @MainActor func defaultImageLoaderCanBeAwaitedFromMainActor() async throws {
    let data = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
    )!
    let asset = DataImageAsset(data: data, uniqueKey: "main-actor-pipeline")
    let request = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: CGSize(width: 8, height: 8)
    )
    let loader = DefaultImageLoader(
        downloader: DefaultImageDataDownloader(),
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )

    let image = try await loader.load(request)

    #expect(image.pixelWidth == 8)
    #expect(image.pixelHeight == 8)
}

private enum AnimatedGIFFixture {
    static let data = Data(base64Encoded: "R0lGODlhEAAQAPf/MQAA//4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAAD/ACH/C05FVFNDQVBFMi4wAwEAAAAh+QQEZAAfACwAAAAAEAAQAAAIHQADCBxIsKDBgwgTKlzIsKHDhxAjSpxIsaLFgQEBACH5BAVkAP8ALAAAAAAQABAAAAgdAAEIHEiwoMGDCBMqXMiwocOHECNKnEixosWBAQEAOw==")!
}

#if canImport(UIKit)
import UIKit

@Test @MainActor func uiKitAsyncImageViewAcceptsPointSizeAndScaleRequestBuilder() {
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
    let asset = DataImageAsset(data: Data([0]), uniqueKey: "sized-uikit-view")

    view.loadImage(
        using: TestImageLoader(),
        request: { targetSize, scale in
            try ImageLoadRequest(
                assetHandle: asset,
                targetSize: targetSize ?? CGSize(width: 120, height: 80),
                scale: scale
            )
        }
    )

    #expect(view.sizingMode == .viewBounds)
}

@Test @MainActor func uiKitAsyncImageViewLoadsAndPlaysImageSequence() async throws {
    let loader = DefaultImageLoader(
        downloader: DefaultImageDataDownloader(),
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = DataImageAsset(data: AnimatedGIFFixture.data, uniqueKey: "platform-ui-sequence")
    let view = AsyncImageView()

    try await view.loadImage(
        asset: asset,
        using: loader,
        targetSize: CGSize(width: 16, height: 16),
        levelOfIntegrity: 0.9
    )

    #expect(view.image != nil)
}
#endif
