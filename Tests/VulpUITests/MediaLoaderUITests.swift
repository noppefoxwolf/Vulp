import Vulp
import VulpUI
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

#if canImport(UIKit)
private actor ImageLoadLifecycleProbe {
    private(set) var loadCount = 0
    private(set) var cancellationCount = 0
    private(set) var completionCount = 0
    private var loadWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cancellationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var completionWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func didStartLoad() async -> Int {
        loadCount += 1
        resumeWaiters(loadCount, from: &loadWaiters)
        return loadCount
    }

    func didCancelLoad() {
        cancellationCount += 1
        resumeWaiters(cancellationCount, from: &cancellationWaiters)
    }

    func didCompleteLoad() {
        completionCount += 1
        resumeWaiters(completionCount, from: &completionWaiters)
    }

    func waitForLoadCount(_ expected: Int) async {
        guard loadCount < expected else { return }
        await withCheckedContinuation { loadWaiters.append((expected, $0)) }
    }

    func waitForCancellationCount(_ expected: Int) async {
        guard cancellationCount < expected else { return }
        await withCheckedContinuation { cancellationWaiters.append((expected, $0)) }
    }

    func waitForCompletionCount(_ expected: Int) async {
        guard completionCount < expected else { return }
        await withCheckedContinuation { completionWaiters.append((expected, $0)) }
    }

    private func resumeWaiters(
        _ actual: Int,
        from waiters: inout [(Int, CheckedContinuation<Void, Never>)]
    ) {
        let ready = waiters.filter { $0.0 <= actual }
        waiters.removeAll { $0.0 <= actual }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }
}

private struct CancellationTrackingImageLoader: ImageLoading {
    let probe: ImageLoadLifecycleProbe

    @concurrent
    func load<Request: MediaImageRequestProtocol>(_ request: Request) async throws -> MediaImage {
        let attempt = await probe.didStartLoad()
        do {
            try await Task.sleep(for: attempt == 1 ? .seconds(30) : .milliseconds(20))
        } catch {
            await probe.didCancelLoad()
            throw error
        }

        let data = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
        )!
        let image = try await ImageIOImageDeserializer().deserialize(data)
        await probe.didCompleteLoad()
        return image
    }
}

private struct SequenceCancellationTrackingImageLoader: MediaImageSequenceLoading {
    let probe: ImageLoadLifecycleProbe

    @concurrent
    func loadSequence(from asset: any MediaAsset) async throws -> ImageSequence {
        try await MediaImageLoader.default.loadSequence(from: asset)
    }

    @concurrent
    func load<Request: MediaImageRequestProtocol>(_ request: Request) async throws -> MediaImage {
        _ = await probe.didStartLoad()
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            await probe.didCancelLoad()
            throw error
        }

        let data = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
        )!
        return try await ImageIOImageDeserializer().deserialize(data)
    }
}

private struct SuccessfulLoadCountingImageLoader: MediaImageSequenceLoading {
    let probe: ImageLoadLifecycleProbe

    @concurrent
    func loadSequence(from asset: any MediaAsset) async throws -> ImageSequence {
        try await MediaImageLoader.default.loadSequence(from: asset)
    }

    @concurrent
    func load<Request: MediaImageRequestProtocol>(_ request: Request) async throws -> MediaImage {
        _ = await probe.didStartLoad()
        let data = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
        )!
        let image = try await ImageIOImageDeserializer().deserialize(data)
        await probe.didCompleteLoad()
        return image
    }
}
#endif

@Test @MainActor func umbrellaProductExposesSwiftUIAsyncImage() throws {
    let request = try ImageLoadRequest(
        assetHandle: DataImageAsset(data: Data(), uniqueKey: "swiftui-view"),
        targetSize: .zero
    )

    let view = VulpUI.AsyncImage(request: request, loader: TestImageLoader()) {
        ProgressView()
    }

    _ = view
}

@Test @MainActor func imageLoaderViewBuildsARequestFromViewSizeAndScale() {
    let view = VulpUI.AsyncImage(
        loader: TestImageLoader(),
        request: { targetSize, scale in
            try ImageLoadRequest(
                assetHandle: DataImageAsset(data: Data(), uniqueKey: "swiftui-builder"),
                targetSize: targetSize ?? .zero,
                scale: scale
            )
        },
        content: { image in
            image.resizable().scaledToFit()
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
    let view = VulpUI.AsyncImage(
        asset: asset,
        loader: loader,
        targetSize: CGSize(width: 16, height: 16),
        levelOfIntegrity: 0.9,
        content: { $0.resizable() }
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

@Test @MainActor func swiftUIImageSequenceCancelsPrefetchedFramesWhenRemoved() async throws {
    let probe = ImageLoadLifecycleProbe()
    let loader = SequenceCancellationTrackingImageLoader(probe: probe)
    let asset = DataImageAsset(data: AnimatedGIFFixture.data, uniqueKey: "swiftui-sequence-cancel")
    let hostingController = UIHostingController(
        rootView: VulpUI.AsyncImage(
            asset: asset,
            loader: loader,
            targetSize: CGSize(width: 16, height: 16),
            prefetchCount: 3,
            content: { $0.resizable() }
        ) {
            ProgressView()
        }
    )
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    hostingController.view.frame = window.bounds
    window.addSubview(hostingController.view)
    hostingController.view.setNeedsLayout()
    hostingController.view.layoutIfNeeded()

    await probe.waitForLoadCount(2)
    hostingController.view.removeFromSuperview()
    await probe.waitForCancellationCount(2)

    #expect(await probe.loadCount == 2)
    #expect(await probe.cancellationCount == 2)
}

@Test @MainActor func uiKitAsyncImageViewCancelsOnRemovalAndReloadsWhenReattached() async throws {
    let probe = ImageLoadLifecycleProbe()
    let loader = CancellationTrackingImageLoader(probe: probe)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
    window.addSubview(view)

    view.loadImage(using: loader) { _, _ in
        try ImageLoadRequest(
            assetHandle: DataImageAsset(data: Data([0]), uniqueKey: "detach-reload-test"),
            targetSize: CGSize(width: 80, height: 80)
        )
    }

    await probe.waitForLoadCount(1)
    view.removeFromSuperview()
    await probe.waitForCancellationCount(1)

    window.addSubview(view)
    await probe.waitForLoadCount(2)
    await probe.waitForCompletionCount(1)

    #expect(view.image != nil)
    #expect(await probe.loadCount == 2)
    #expect(await probe.cancellationCount == 1)
}

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

@Test @MainActor func swiftUIImageDoesNotReloadSuccessfulRequestWhenReappearing() async throws {
    let probe = ImageLoadLifecycleProbe()
    let loader = SuccessfulLoadCountingImageLoader(probe: probe)
    let request = try ImageLoadRequest(
        assetHandle: DataImageAsset(data: Data([0]), uniqueKey: "swiftui-reappear-success"),
        targetSize: CGSize(width: 16, height: 16)
    )
    let hostingController = UIHostingController(
        rootView: VulpUI.AsyncImage(
            request: request,
            loader: loader,
            content: { $0.resizable() }
        ) {
            ProgressView()
        }
    )
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    hostingController.view.frame = window.bounds
    window.addSubview(hostingController.view)
    hostingController.view.setNeedsLayout()
    hostingController.view.layoutIfNeeded()

    await probe.waitForCompletionCount(1)
    hostingController.view.removeFromSuperview()
    window.addSubview(hostingController.view)
    hostingController.view.setNeedsLayout()
    hostingController.view.layoutIfNeeded()
    try await Task.sleep(for: .milliseconds(100))

    #expect(await probe.loadCount == 1)
    #expect(await probe.completionCount == 1)
}

@Test @MainActor func swiftUIImageDoesNotReloadSuccessfulStaticSequenceWhenReappearing() async throws {
    let probe = ImageLoadLifecycleProbe()
    let loader = SuccessfulLoadCountingImageLoader(probe: probe)
    let asset = DataImageAsset(
        data: Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
        )!,
        uniqueKey: "swiftui-static-sequence-reappear"
    )
    let hostingController = UIHostingController(
        rootView: VulpUI.AsyncImage(
            asset: asset,
            loader: loader,
            targetSize: CGSize(width: 16, height: 16),
            content: { $0.resizable() }
        ) {
            ProgressView()
        }
    )
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    hostingController.view.frame = window.bounds
    window.addSubview(hostingController.view)
    hostingController.view.setNeedsLayout()
    hostingController.view.layoutIfNeeded()

    await probe.waitForCompletionCount(1)
    hostingController.view.removeFromSuperview()
    window.addSubview(hostingController.view)
    hostingController.view.setNeedsLayout()
    hostingController.view.layoutIfNeeded()
    try await Task.sleep(for: .milliseconds(100))

    #expect(await probe.loadCount == 1)
    #expect(await probe.completionCount == 1)
}
#endif
