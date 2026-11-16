#if canImport(UIKit)
import UIKit
import Testing
import SwiftUI
import Vulp
import VulpUI
@testable import Vulp_UIKit

/// Ignores cancellation deliberately so tests can finish superseded work in any order.
private actor ImageGate {
    private var pending: [Int: CheckedContinuation<CGImage?, Never>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var count = 0

    func image() async -> CGImage? {
        count += 1
        let index = count
        return await withCheckedContinuation { continuation in
            pending[index] = continuation
            let ready = waiters.filter { $0.0 <= count }
            waiters.removeAll { $0.0 <= count }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForStart(_ index: Int = 1) async {
        guard count < index else { return }
        await withCheckedContinuation { waiters.append((index, $0)) }
    }

    func finish(_ index: Int = 1, with image: CGImage?) {
        pending.removeValue(forKey: index)?.resume(returning: image)
    }
}

private enum LoaderFailure: Error { case missingImage }

private func placeholderRunsOnMainThread() -> Bool { Thread.isMainThread }

private struct GatedLoader: MediaImageLoading {
    let gate: ImageGate

    @concurrent
    func load<Request: MediaImageRequestProtocol>(_ request: Request, priority: TaskPriority) async throws -> CGImage {
        let image = await gate.image()
        try Task.checkCancellation()
        guard let image else { throw LoaderFailure.missingImage }
        return image
    }
}

@MainActor
private func fixtureImage() -> CGImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
    return renderer.image { context in
        context.cgContext.setFillColor(UIColor.red.cgColor)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }.cgImage!
}

@MainActor
private func request(_ source: String = "source", size: CGSize = CGSize(width: 40, height: 40)) throws -> MediaImageRequest {
    try MediaImageRequest(asset: DataMediaAsset(data: Data(), uniqueKey: source), targetSize: size)
}

@MainActor
@Test func placeholderCannotReplaceImageAfterGenerationHasStarted() async throws {
    let gate = ImageGate()
    let view = AsyncImageView()
    let image = fixtureImage()
    view.loadImage(url: URL(string: "https://example.com/a")!, placeholder: { await gate.image() })
    await gate.waitForStart()
    let task = view.placeholderLoading.task
    view.displayLoadedContent(.still(image), cacheIdentifier: "loaded")
    await gate.finish(with: fixtureImage())
    await task?.value
    #expect(view.image === image)
}

@MainActor
@Test func replacingSourceRejectsPlaceholderAlreadyBeingGenerated() async throws {
    let oldGate = ImageGate()
    let newGate = ImageGate()
    let view = AsyncImageView()
    let image = fixtureImage()
    view.loadImage(url: URL(string: "https://example.com/a")!, placeholder: {
        #expect(!placeholderRunsOnMainThread())
        return await oldGate.image()
    })
    await oldGate.waitForStart()
    let oldTask = view.placeholderLoading.task
    view.loadImage(url: URL(string: "https://example.com/b")!, placeholder: { await newGate.image() })
    await newGate.waitForStart()
    let newTask = view.placeholderLoading.task
    await newGate.finish(with: image)
    await newTask?.value
    await oldGate.finish(with: fixtureImage())
    await oldTask?.value
    #expect(view.image === image)
}

@MainActor
@Test func detachingSuspendsPlaceholderAndReattachingRestartsIt() async throws {
    let gate = ImageGate()
    let view = AsyncImageView() // Zero bounds keep the network image from loading.
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    window.addSubview(view)
    view.loadImage(url: URL(string: "https://example.com/a")!, placeholder: { await gate.image() })
    await gate.waitForStart()
    let oldTask = view.placeholderLoading.task
    view.removeFromSuperview()
    #expect(oldTask?.isCancelled == true)
    let image = fixtureImage()
    await gate.finish(with: image)
    await oldTask?.value
    #expect(view.image == nil)
    window.addSubview(view)
    await gate.waitForStart(2)
    let newTask = view.placeholderLoading.task
    await gate.finish(2, with: image)
    await newTask?.value
    #expect(view.image === image)
}

@MainActor
@Test func repeatedRequestReusesInFlightAndLoadedImage() async throws {
    let gate = ImageGate()
    let loader = GatedLoader(gate: gate)
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let window = UIWindow(frame: view.frame)
    window.addSubview(view)
    let completion = AsyncStream<Void>.makeStream()
    var results = completion.stream.makeAsyncIterator()
    view.loadImage(using: loader, request: { _, _ in try request() }, onCompletion: { _ in completion.continuation.yield(()) })
    await gate.waitForStart()
    view.loadImage(using: loader, request: { _, _ in try request() }, onCompletion: { _ in completion.continuation.yield(()) })
    let image = fixtureImage()
    await gate.finish(with: image)
    await results.next()
    #expect(await gate.count == 1)
    #expect(view.image === image)
    view.loadImage(using: loader, request: { _, _ in try request() })
    #expect(view.image === image)
    #expect(await gate.count == 1)
}

@MainActor
@Test func placeholderUpdateDoesNotInvalidateExplicitImageLoad() async throws {
    let imageGate = ImageGate()
    let placeholderGate = ImageGate()
    let view = AsyncImageView()
    let image = fixtureImage()
    let task = Task { try await view.loadImage(asset: DataMediaAsset(data: Data(), uniqueKey: "a"), using: GatedLoader(gate: imageGate), targetSize: CGSize(width: 40, height: 40)) }
    await imageGate.waitForStart()
    view.setPlaceholder { await placeholderGate.image() }
    await placeholderGate.waitForStart()
    await imageGate.finish(with: image)
    try await task.value
    await placeholderGate.finish(with: fixtureImage())
    #expect(view.image === image)
}

@MainActor
@Test func resizingRetainsLoadedImageAndDoesNotGeneratePlaceholder() async throws {
    let gate = ImageGate()
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    window.addSubview(view)
    let completion = AsyncStream<Void>.makeStream()
    var results = completion.stream.makeAsyncIterator()
    view.loadImage(using: GatedLoader(gate: gate), request: { size, _ in
        try request(size: size!)
    }, onCompletion: { _ in completion.continuation.yield(()) })
    await gate.waitForStart()
    let firstImage = fixtureImage()
    await gate.finish(with: firstImage)
    await results.next()
    view.bounds.size = CGSize(width: 80, height: 80)
    view.setNeedsLayout()
    view.layoutIfNeeded()
    await gate.waitForStart(2)
    #expect(view.image === firstImage)
    view.setPlaceholder { firstImage }
    #expect(view.placeholderLoading.task == nil)
    let secondImage = fixtureImage()
    await gate.finish(2, with: secondImage)
    await results.next()
    #expect(view.image === secondImage)
}

@MainActor
@Test func failedRequestCanBeRetriedWithoutChangingSource() async throws {
    let gate = ImageGate()
    let loader = GatedLoader(gate: gate)
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let window = UIWindow(frame: view.frame)
    window.addSubview(view)
    let completion = AsyncStream<Void>.makeStream()
    var results = completion.stream.makeAsyncIterator()
    view.loadImage(using: loader, request: { _, _ in try request() }, onCompletion: { _ in completion.continuation.yield(()) })
    await gate.waitForStart()
    await gate.finish(with: nil)
    await results.next()
    view.loadImage(using: loader, request: { _, _ in try request() }, onCompletion: { _ in completion.continuation.yield(()) })
    await gate.waitForStart(2)
    let image = fixtureImage()
    await gate.finish(2, with: image)
    await results.next()
    #expect(view.image === image)
}

@MainActor
@Test func swiftUIPlaceholderIDUpdatesProviderWithoutChangingURL() async throws {
    let gate = ImageGate()
    let url = URL(string: "https://example.com/a")!
    let host = UIHostingController(rootView: VulpUI.AsyncImage(url: url).frame(width: 0, height: 0))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    window.addSubview(host.view)
    host.view.layoutIfNeeded()
    let view = try #require(findImageView(in: host.view))
    let imageGeneration = view.imageLoadGeneration
    host.rootView = VulpUI.AsyncImage(url: url, placeholderID: "blurhash", placeholder: { await gate.image() }).frame(width: 0, height: 0)
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    await gate.waitForStart()
    #expect(view.imageLoadGeneration == imageGeneration)
    let task = view.placeholderLoading.task
    let image = fixtureImage()
    await gate.finish(with: image)
    await task?.value
    #expect(view.image === image)
}

@MainActor
private func findImageView(in view: UIView) -> AsyncImageView? {
    if let imageView = view as? AsyncImageView { return imageView }
    for child in view.subviews {
        if let imageView = findImageView(in: child) { return imageView }
    }
    return nil
}

@MainActor
@Test func supersededExplicitLoadCannotReplaceNewSource() async throws {
    let oldGate = ImageGate()
    let newGate = ImageGate()
    let view = AsyncImageView()
    let first = Task {
        try await view.loadImage(asset: DataMediaAsset(data: Data(), uniqueKey: "old"), using: GatedLoader(gate: oldGate), targetSize: CGSize(width: 40, height: 40))
    }
    await oldGate.waitForStart()
    let second = Task {
        try await view.loadImage(asset: DataMediaAsset(data: Data(), uniqueKey: "new"), using: GatedLoader(gate: newGate), targetSize: CGSize(width: 40, height: 40))
    }
    await newGate.waitForStart()
    let image = fixtureImage()
    await newGate.finish(with: image)
    try await second.value
    await oldGate.finish(with: fixtureImage())
    do {
        try await first.value
        Issue.record("Superseded load should throw CancellationError")
    } catch is CancellationError {
        // Expected even though the provider ignored cancellation.
    }
    #expect(view.image === image)
}

@MainActor
@Test func failedPlaceholderDoesNotFailImageRequest() async throws {
    let gate = ImageGate()
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let window = UIWindow(frame: view.frame)
    window.addSubview(view)
    let completion = AsyncStream<Void>.makeStream()
    var results = completion.stream.makeAsyncIterator()
    view.loadImage(using: GatedLoader(gate: gate), placeholder: { throw LoaderFailure.missingImage }, request: { _, _ in try request() }, onCompletion: { _ in completion.continuation.yield(()) })
    let placeholderTask = view.placeholderLoading.task
    await placeholderTask?.value
    await gate.waitForStart()
    let image = fixtureImage()
    await gate.finish(with: image)
    await results.next()
    #expect(view.image === image)
}

@MainActor
@Test func layoutSelectingDifferentSourceCancelsPreviousPlaceholder() async throws {
    let imageGate = ImageGate()
    let placeholderGate = ImageGate()
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    window.addSubview(view)
    let completion = AsyncStream<Void>.makeStream()
    var results = completion.stream.makeAsyncIterator()
    view.loadImage(using: GatedLoader(gate: imageGate), placeholder: { await placeholderGate.image() }, request: { size, _ in
        try request(size!.width < 60 ? "old" : "new", size: size!)
    }, onCompletion: { _ in completion.continuation.yield(()) })
    await imageGate.waitForStart()
    await placeholderGate.waitForStart()
    let oldPlaceholderTask = view.placeholderLoading.task
    view.bounds.size = CGSize(width: 80, height: 80)
    view.setNeedsLayout()
    view.layoutIfNeeded()
    await imageGate.waitForStart(2)
    #expect(oldPlaceholderTask?.isCancelled == true)
    await placeholderGate.finish(with: fixtureImage())
    await oldPlaceholderTask?.value
    #expect(view.image == nil)
    await imageGate.finish(with: fixtureImage())
    let image = fixtureImage()
    await imageGate.finish(2, with: image)
    await results.next()
    #expect(view.image === image)
}
#endif
