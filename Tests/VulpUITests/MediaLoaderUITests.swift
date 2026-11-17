import Vulp
import VulpUI
import SwiftUI
import Testing

private func decodeFixture(_ data: Data) async throws -> MediaImage {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("VulpUITests-\(UUID().uuidString)", isDirectory: false)
    defer { try? FileManager.default.removeItem(at: url) }
    try data.write(to: url)
    return try await ImageIOImageDecoder().decode(from: url, options: .firstFrame, maximumPixelDimension: nil)
}

private struct TestImageLoader: MediaImageLoading {
    @concurrent
    func load<Request: MediaImageRequestProtocol>(_ request: Request, priority: TaskPriority) async throws -> MediaImage {
        let isolation: (any Actor)? = #isolation
        if let isolation {
            throw TestImageLoaderError.unexpectedActorIsolation(String(describing: isolation))
        }

        let data = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
        )!
        return try await decodeFixture(data)
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

private struct CancellationTrackingImageLoader: MediaImageLoading {
    let probe: ImageLoadLifecycleProbe

    @concurrent
    func load<Request: MediaImageRequestProtocol>(
        _ request: Request,
        priority: TaskPriority
    ) async throws -> MediaImage {
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
        let image = try await decodeFixture(data)
        await probe.didCompleteLoad()
        return image
    }
}

private actor SequenceRequestRoutingProbe {
    private(set) var firstFrameRequestCount = 0
    private(set) var indexedFrameRequestCount = 0

    func record(_ options: ImageDecodingOptions) {
        switch options {
        case .firstFrame:
            firstFrameRequestCount += 1
        case .frame:
            indexedFrameRequestCount += 1
        }
    }
}

private struct SequenceRequestRoutingImageLoader: MediaImageLoading {
    let probe: SequenceRequestRoutingProbe

    @concurrent
    func loadSequence(from asset: any MediaAsset) async throws -> ImageSequence {
        try await MediaImageLoader.default.loadSequence(from: asset)
    }

    @concurrent
    func load<Request: MediaImageRequestProtocol>(
        _ request: Request,
        priority: TaskPriority
    ) async throws -> MediaImage {
        await probe.record(request.decodingOptions)
        return try await MediaImageLoader.default.load(request, priority: priority)
    }
}

private struct SequenceCancellationTrackingImageLoader: MediaImageSequenceLoading {
    let probe: ImageLoadLifecycleProbe

    @concurrent
    func loadSequence(from asset: any MediaAsset) async throws -> ImageSequence {
        try await MediaImageLoader.default.loadSequence(from: asset)
    }

    @concurrent
    func load<Request: MediaImageRequestProtocol>(
        _ request: Request,
        priority: TaskPriority
    ) async throws -> MediaImage {
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
        return try await decodeFixture(data)
    }
}

private struct SuccessfulLoadCountingImageLoader: MediaImageSequenceLoading {
    let probe: ImageLoadLifecycleProbe

    @concurrent
    func loadSequence(from asset: any MediaAsset) async throws -> ImageSequence {
        try await MediaImageLoader.default.loadSequence(from: asset)
    }

    @concurrent
    func load<Request: MediaImageRequestProtocol>(
        _ request: Request,
        priority: TaskPriority
    ) async throws -> MediaImage {
        _ = await probe.didStartLoad()
        let data = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
        )!
        let image = try await decodeFixture(data)
        await probe.didCompleteLoad()
        return image
    }
}
#endif

@Test @MainActor func umbrellaProductExposesSwiftUIAsyncImageTimelineView() throws {
    let request = try MediaImageRequest(
        asset: DataMediaAsset(data: Data(), uniqueKey: "swiftui-view"),
        targetSize: .zero
    )

    let view = VulpUI.AsyncImageTimelineView(request: request, loader: TestImageLoader()) {
        ProgressView()
    }

    _ = view
}

@Test @MainActor func imageLoaderViewBuildsARequestFromViewSizeAndScale() {
    let view = VulpUI.AsyncImageTimelineView(
        loader: TestImageLoader(),
        request: { targetSize, scale in
            try MediaImageRequest(
                asset: DataMediaAsset(data: Data(), uniqueKey: "swiftui-builder"),
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
    let loader = DefaultMediaImageLoader(
        downloader: DefaultAssetDataDownloader(),
        decoders: [ImageIOImageDecoder()],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = DataMediaAsset(data: Data([0]), uniqueKey: "sequence-view")
    let view = VulpUI.AsyncImageTimelineView(
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
    let request = try MediaImageRequest(
        asset: DataMediaAsset(data: Data(), uniqueKey: "main-actor-test"),
        targetSize: .zero
    )
    let image = try await TestImageLoader().load(request)

    #expect(image.width == 1)
    #expect(image.height == 1)
}

@Test @MainActor func defaultImageLoaderCanBeAwaitedFromMainActor() async throws {
    let data = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
    )!
    let asset = DataMediaAsset(data: data, uniqueKey: "main-actor-pipeline")
    let request = try MediaImageRequest(
        asset: asset,
        targetSize: CGSize(width: 8, height: 8)
    )
    let loader = DefaultMediaImageLoader(
        downloader: DefaultAssetDataDownloader(),
        decoders: [ImageIOImageDecoder()],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )

    let image = try await loader.load(request)

    // The pipeline preserves the 1×1 source rather than upscaling to the request bounds.
    #expect(image.width == 1)
    #expect(image.height == 1)
}

private enum AnimatedGIFFixture {
    static let data = Data(base64Encoded: "R0lGODlhEAAQAPf/MQAA//4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAAD/ACH/C05FVFNDQVBFMi4wAwEAAAAh+QQEZAAfACwAAAAAEAAQAAAIHQADCBxIsKDBgwgTKlzIsKHDhxAjSpxIsaLFgQEBACH5BAVkAP8ALAAAAAAQABAAAAgdAAEIHEiwoMGDCBMqXMiwocOHECNKnEixosWBAQEAOw==")!
}

#if canImport(UIKit)
import UIKit

@Test @MainActor func swiftUIAsyncImageMapsSwiftUIConfigurationToUIKit() throws {
    for mode in [SwiftUI.ContentMode.fit, .fill] {
        let sizingMode: VulpUI.AsyncImage.SizingMode = .explicitPixels
        let view = VulpUI.AsyncImage(
            url: URL(string: "about:blank")!,
            contentMode: mode,
            sizingMode: sizingMode
        )
        func requireRepresentable<Value: UIViewRepresentable>(_ value: Value) {}
        requireRepresentable(view)
        let host = UIHostingController(rootView: view.frame(width: 80, height: 60))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 80, height: 60))
        host.view.frame = window.bounds
        window.addSubview(host.view)
        host.view.layoutIfNeeded()

        let imageView = try #require(findAsyncImageView(in: host.view))
        #expect(imageView.contentMode == (mode == .fit ? .scaleAspectFit : .scaleAspectFill))
        #expect(imageView.sizingMode == .explicitPixels)
    }
}

@Test @MainActor func swiftUIAsyncImageCoordinatorForwardsCurrentCompletion() async throws {
    let url = URL(string: "about:blank")!
    let firstStart = AsyncStream<Void>.makeStream()
    let secondStart = AsyncStream<Void>.makeStream()
    let first = AsyncStream<Result<CGImage, any Error>>.makeStream()
    let second = AsyncStream<Result<CGImage, any Error>>.makeStream()
    let host = UIHostingController(rootView: VulpUI.AsyncImage(
        url: url,
        onStart: { firstStart.continuation.yield(()) },
        onCompletion: { first.continuation.yield($0) }
    ).frame(width: 0, height: 0))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 80, height: 60))
    window.addSubview(host.view)
    host.view.layoutIfNeeded()
    let view = try #require(findAsyncImageView(in: host.view))
    let delegate = try #require(view.delegate)
    #expect(delegate is VulpUI.AsyncImage.Coordinator)
    delegate.asyncImageViewDidStartLoading(view)
    var firstStarts = firstStart.stream.makeAsyncIterator()
    #expect(await firstStarts.next() != nil)
    delegate.asyncImageView(view, didComplete: .failure(CancellationError()))
    var firstResults = first.stream.makeAsyncIterator()
    if case .failure(let error) = await firstResults.next() {
        #expect(error is CancellationError)
    } else {
        Issue.record("Coordinator should forward failure")
    }

    host.rootView = VulpUI.AsyncImage(
        url: url,
        onStart: { secondStart.continuation.yield(()) },
        onCompletion: { second.continuation.yield($0) }
    ).frame(width: 0, height: 0)
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    #expect(view.delegate === delegate)
    delegate.asyncImageViewDidStartLoading(view)
    var secondStarts = secondStart.stream.makeAsyncIterator()
    #expect(await secondStarts.next() != nil)
    delegate.asyncImageView(view, didComplete: .failure(CancellationError()))
    var secondResults = second.stream.makeAsyncIterator()
    if case .failure(let error) = await secondResults.next() {
        #expect(error is CancellationError)
    } else {
        Issue.record("Coordinator should use the updated completion")
    }
}

@Test @MainActor func swiftUIAsyncImageUsesProposedViewBounds() {
    let expectedSizes = [
        CGSize(width: 310, height: 175),
        CGSize(width: 310, height: 413),
    ]

    for expectedSize in expectedSizes {
        let hostingController = UIHostingController(
            rootView: VulpUI.AsyncImage(url: URL(string: "about:blank")!)
                .frame(width: expectedSize.width, height: expectedSize.height)
        )
        let window = UIWindow(frame: CGRect(origin: .zero, size: expectedSize))
        hostingController.view.frame = window.bounds
        window.addSubview(hostingController.view)
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()

        let imageView = findAsyncImageView(in: hostingController.view)
        #expect(imageView?.bounds.size == expectedSize)
    }
}

@Test @MainActor func swiftUIExplicitPixelAsyncImageRespectsFiniteProposals() throws {
    #expect(try measuredExplicitPixelAsyncImageSize(width: 310, height: 175) == CGSize(width: 310, height: 175))
    #expect(try measuredExplicitPixelAsyncImageSize(width: 310, height: nil) == CGSize(width: 310, height: 155))
    #expect(try measuredExplicitPixelAsyncImageSize(width: nil, height: 175) == CGSize(width: 350, height: 175))
    #expect(try measuredExplicitPixelAsyncImageSize(width: nil, height: nil) == CGSize(width: 40, height: 20))
}

@MainActor
private func measuredExplicitPixelAsyncImageSize(width: CGFloat?, height: CGFloat?) throws -> CGSize {
    let hostingController = UIHostingController(
        rootView: VulpUI.AsyncImage(
            url: URL(string: "about:blank")!,
            sizingMode: .explicitPixels
        )
        .frame(width: width, height: height)
    )
    // Measure image content independently of the simulator device's safe-area insets.
    hostingController.safeAreaRegions = []
    let windowSize = CGSize(width: width ?? 320, height: height ?? 240)
    let window = UIWindow(frame: CGRect(origin: .zero, size: windowSize))
    hostingController.view.frame = window.bounds
    window.addSubview(hostingController.view)
    hostingController.view.setNeedsLayout()
    hostingController.view.layoutIfNeeded()

    let imageView = try #require(findAsyncImageView(in: hostingController.view))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    imageView.image = UIGraphicsImageRenderer(
        size: CGSize(width: 40, height: 20),
        format: format
    ).image { context in
        context.cgContext.setFillColor(UIColor.black.cgColor)
        context.cgContext.fill(CGRect(origin: .zero, size: CGSize(width: 40, height: 20)))
    }.cgImage

    return hostingController.sizeThatFits(in: CGSize(
        width: width ?? .infinity,
        height: height ?? .infinity
    ))
}

@MainActor
private func findAsyncImageView(in view: UIView) -> AsyncImageView? {
    if let imageView = view as? AsyncImageView {
        return imageView
    }
    for subview in view.subviews {
        if let imageView = findAsyncImageView(in: subview) {
            return imageView
        }
    }
    return nil
}

@Test @MainActor func swiftUIImageSequenceCancelsPrefetchedFramesWhenRemoved() async throws {
    let probe = ImageLoadLifecycleProbe()
    let loader = SequenceCancellationTrackingImageLoader(probe: probe)
    let asset = DataMediaAsset(data: AnimatedGIFFixture.data, uniqueKey: "swiftui-sequence-cancel")
    let hostingController = UIHostingController(
        rootView: VulpUI.AsyncImageTimelineView(
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
        try MediaImageRequest(
            asset: DataMediaAsset(data: Data([0]), uniqueKey: "detach-reload-test"),
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

@Test @MainActor func uiKitAsyncImageViewKeepsSuccessfulRequestWhenReattached() async throws {
    let probe = ImageLoadLifecycleProbe()
    let loader = SuccessfulLoadCountingImageLoader(probe: probe)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
    window.addSubview(view)

    view.loadImage(using: loader) { _, _ in
        try MediaImageRequest(
            asset: DataMediaAsset(data: Data([0]), uniqueKey: "successful-request-reappear"),
            targetSize: CGSize(width: 80, height: 80)
        )
    }
    await probe.waitForCompletionCount(1)
    try await Task.sleep(for: .milliseconds(20))
    let loadedImage = try #require(view.image)

    view.removeFromSuperview()
    window.addSubview(view)
    view.layoutIfNeeded()
    try await Task.sleep(for: .milliseconds(100))

    #expect(view.image === loadedImage)
    #expect(await probe.loadCount == 1)
    #expect(await probe.completionCount == 1)
}

@Test @MainActor func uiKitAsyncImageViewAcceptsPointSizeAndScaleRequestBuilder() {
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
    let asset = DataMediaAsset(data: Data([0]), uniqueKey: "sized-uikit-view")

    view.loadImage(
        using: TestImageLoader(),
        request: { targetSize, scale in
            try MediaImageRequest(
                asset: asset,
                targetSize: targetSize ?? CGSize(width: 120, height: 80),
                scale: scale
            )
        }
    )

    #expect(view.sizingMode == .viewBounds)
}

@Test @MainActor func uiKitAsyncImageViewLoadsAndPlaysImageSequence() async throws {
    let loader = DefaultMediaImageLoader(
        downloader: DefaultAssetDataDownloader(),
        decoders: [ImageIOImageDecoder()],
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = DataMediaAsset(data: AnimatedGIFFixture.data, uniqueKey: "platform-ui-sequence")
    let view = AsyncImageView()

    try await view.loadImage(
        asset: asset,
        using: loader,
        targetSize: CGSize(width: 16, height: 16),
        levelOfIntegrity: 0.9
    )

    #expect(view.image != nil)
}

@Test @MainActor func uiKitRequestAutomaticallyUsesSequenceFramesWhenAvailable() async throws {
    let probe = SequenceRequestRoutingProbe()
    let loader = SequenceRequestRoutingImageLoader(probe: probe)
    let asset = DataMediaAsset(data: AnimatedGIFFixture.data, uniqueKey: "request-sequence-routing")
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
    let view = AsyncImageView(frame: window.bounds)
    window.addSubview(view)

    let completion = AsyncStream<Result<CGImage, any Error>>.makeStream()
    var results = completion.stream.makeAsyncIterator()
    let delegate = ImageViewCompletionDelegate { completion.continuation.yield($0) }
    view.delegate = delegate
    defer { withExtendedLifetime(delegate) {} }
    view.loadImage(
        using: loader,
        request: { _, _ in
            try MediaImageRequest(asset: asset, targetSize: CGSize(width: 16, height: 16))
        }
    )
    let result = try #require(await results.next())

    #expect(try result.get().width == 16)
    #expect(await probe.indexedFrameRequestCount > 0)
    #expect(await probe.firstFrameRequestCount == 0)
}

@Test @MainActor func swiftUIImageDoesNotReloadSuccessfulRequestWhenReappearing() async throws {
    let probe = ImageLoadLifecycleProbe()
    let loader = SuccessfulLoadCountingImageLoader(probe: probe)
    let request = try MediaImageRequest(
        asset: DataMediaAsset(data: Data([0]), uniqueKey: "swiftui-reappear-success"),
        targetSize: CGSize(width: 16, height: 16)
    )
    let hostingController = UIHostingController(
        rootView: VulpUI.AsyncImageTimelineView(
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
    let completion = AsyncStream<Void>.makeStream()
    var results = completion.stream.makeAsyncIterator()
    let asset = DataMediaAsset(
        data: Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
        )!,
        uniqueKey: "swiftui-static-sequence-reappear"
    )
    let hostingController = UIHostingController(
        rootView: VulpUI.AsyncImageTimelineView(
            asset: asset,
            loader: loader,
            targetSize: CGSize(width: 16, height: 16),
            onCompletion: { _ in completion.continuation.yield(()) },
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

    // Wait for the view to apply the image, not merely for the loader to return it.
    await results.next()
    hostingController.view.removeFromSuperview()
    window.addSubview(hostingController.view)
    hostingController.view.setNeedsLayout()
    hostingController.view.layoutIfNeeded()
    try await Task.sleep(for: .milliseconds(100))

    #expect(await probe.loadCount == 1)
    #expect(await probe.completionCount == 1)
}
#endif
