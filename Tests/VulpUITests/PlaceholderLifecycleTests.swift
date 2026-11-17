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
    view.loadImage(url: URL(string: "https://example.com/a")!)
    view.setPlaceholder(PlaceholderAsset(id: "placeholder-0") { await gate.image() })
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
    view.loadImage(url: URL(string: "https://example.com/a")!)
    view.setPlaceholder(PlaceholderAsset(id: "placeholder-1") {
        #expect(!placeholderRunsOnMainThread())
        return await oldGate.image()
    })
    await oldGate.waitForStart()
    let oldTask = view.placeholderLoading.task
    view.loadImage(url: URL(string: "https://example.com/b")!)
    view.setPlaceholder(PlaceholderAsset(id: "placeholder-2") { await newGate.image() })
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
    view.loadImage(url: URL(string: "https://example.com/a")!)
    view.setPlaceholder(PlaceholderAsset(id: "placeholder-3") { await gate.image() })
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
    view.setPlaceholder(PlaceholderAsset(id: "placeholder-4") { await placeholderGate.image() })
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
    view.setPlaceholder(PlaceholderAsset(id: "placeholder-5") { firstImage })
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
    host.rootView = VulpUI.AsyncImage(url: url, placeholder: PlaceholderAsset(id: "blurhash") { await gate.image() }).frame(width: 0, height: 0)
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    await gate.waitForStart()
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
    view.setPlaceholder(PlaceholderAsset(id: "placeholder-6") { throw LoaderFailure.missingImage })
    view.loadImage(using: GatedLoader(gate: gate), request: { _, _ in try request() }, onCompletion: { _ in completion.continuation.yield(()) })
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
    view.setPlaceholder(PlaceholderAsset(id: "placeholder-7") { await placeholderGate.image() })
    view.loadImage(using: GatedLoader(gate: imageGate), request: { size, _ in
        try request(size!.width < 60 ? "old" : "new", size: size!)
    }, onCompletion: { _ in completion.continuation.yield(()) })
    await imageGate.waitForStart()
    await placeholderGate.waitForStart()
    let oldPlaceholderTask = view.placeholderLoading.task
    view.bounds.size = CGSize(width: 80, height: 80)
    view.setNeedsLayout()
    view.layoutIfNeeded()
    await imageGate.waitForStart(2)
    await placeholderGate.waitForStart(2)
    let newPlaceholderTask = view.placeholderLoading.task
    #expect(oldPlaceholderTask?.isCancelled == true)
    await placeholderGate.finish(with: fixtureImage())
    await oldPlaceholderTask?.value
    #expect(view.image == nil)
    await imageGate.finish(with: fixtureImage())
    let image = fixtureImage()
    await imageGate.finish(2, with: image)
    await results.next()
    await placeholderGate.finish(2, with: fixtureImage())
    await newPlaceholderTask?.value
    #expect(view.image === image)
}

@MainActor
@Test func `Repeated request keeps its rendered placeholder`() async throws {
    let gate = ImageGate()
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let window = UIWindow(frame: view.frame)
    window.addSubview(view)
    let placeholder = fixtureImage()
    let loader = GatedLoader(gate: gate)
    view.setPlaceholder(PlaceholderAsset(id: "placeholder-8") { placeholder })
    view.loadImage(using: loader, request: { _, _ in try request() })
    let placeholderTask = view.placeholderLoading.task
    await gate.waitForStart()
    await placeholderTask?.value
    #expect(view.image === placeholder)
    view.loadImage(using: loader, request: { _, _ in try request() })
    #expect(view.image === placeholder)
    #expect(view.placeholderLoading.task == nil)
    await gate.finish(with: fixtureImage())
    await view.imageLoading.waitForManagedLoad()
}

@MainActor
@Test func `Repeated request keeps its running placeholder generation`() async throws {
    let imageGate = ImageGate()
    let placeholderGate = ImageGate()
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let window = UIWindow(frame: view.frame)
    window.addSubview(view)
    let loader = GatedLoader(gate: imageGate)
    view.setPlaceholder(PlaceholderAsset(id: "placeholder-9") { await placeholderGate.image() })
    view.loadImage(using: loader, request: { _, _ in try request() })
    await imageGate.waitForStart()
    await placeholderGate.waitForStart()
    let originalTask = try #require(view.placeholderLoading.task)
    view.loadImage(using: loader, request: { _, _ in try request() })
    #expect(!originalTask.isCancelled)
    #expect(view.placeholderLoading.task == originalTask)
    let replacementTask = view.placeholderLoading.task
    let placeholder = fixtureImage()
    await placeholderGate.finish(with: placeholder)
    await originalTask.value
    await replacementTask?.value
    #expect(view.image === placeholder)
    await imageGate.finish(with: fixtureImage())
    await view.imageLoading.waitForManagedLoad()
}

@MainActor
@Test func `Explicit image load survives temporary reattachment`() async throws {
    let gate = ImageGate()
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let window = UIWindow(frame: view.frame)
    window.addSubview(view)
    let task = Task {
        try await view.loadImage(asset: DataMediaAsset(data: Data(), uniqueKey: "a"), using: GatedLoader(gate: gate), targetSize: CGSize(width: 40, height: 40))
    }
    await gate.waitForStart()
    view.removeFromSuperview()
    window.addSubview(view)
    let image = fixtureImage()
    await gate.finish(with: image)
    await #expect(throws: Never.self) { try await task.value }
    #expect(view.image === image)
}

private struct CancellingLoader: MediaImageLoading {
    let gate: ImageGate

    @concurrent
    func load<Request: MediaImageRequestProtocol>(_ request: Request, priority: TaskPriority) async throws -> CGImage {
        guard let image = await gate.image() else { throw CancellationError() }
        return image
    }
}

@MainActor
@Test func `Cancelled loader releases its request identifier for retry`() async throws {
    let gate = ImageGate()
    let loader = CancellingLoader(gate: gate)
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let window = UIWindow(frame: view.frame)
    window.addSubview(view)
    view.loadImage(using: loader, request: { _, _ in try request() })
    await gate.waitForStart()
    try #require(view.imageLoading.hasManagedLoad)
    await gate.finish(with: nil)
    await view.imageLoading.waitForManagedLoad()
    view.loadImage(using: loader, request: { _, _ in try request() })
    guard view.imageLoading.hasManagedLoad else {
        Issue.record("The cancelled request must be retryable with the same identifier")
        return
    }
    await gate.waitForStart(2)
    let image = fixtureImage()
    await gate.finish(2, with: image)
    await view.imageLoading.waitForManagedLoad()
    #expect(view.image === image)
}

@MainActor
@Test func `UIKit owns placeholder identity without restarting the image request`() async throws {
    let imageGate = ImageGate()
    let oldGate = ImageGate()
    let newGate = ImageGate()
    let view = AsyncImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    let window = UIWindow(frame: view.frame)
    window.addSubview(view)
    let loader = GatedLoader(gate: imageGate)
    view.setPlaceholder(PlaceholderAsset(id: "old") { await oldGate.image() })
    view.loadImage(using: loader, request: { _, _ in try request() })
    await imageGate.waitForStart()
    await oldGate.waitForStart()
    let oldTask = try #require(view.placeholderLoading.task)
    view.setPlaceholder(PlaceholderAsset(id: "old") { nil })
    view.loadImage(using: loader, request: { _, _ in try request() })
    #expect(view.placeholderLoading.task == oldTask)
    #expect(!oldTask.isCancelled)
    view.setPlaceholder(PlaceholderAsset(id: "new") { await newGate.image() })
    view.loadImage(using: loader, request: { _, _ in try request() })
    await newGate.waitForStart()
    #expect(oldTask.isCancelled)
    #expect(await imageGate.count == 1)
    let placeholderTask = view.placeholderLoading.task
    let placeholder = fixtureImage()
    await newGate.finish(with: placeholder)
    await placeholderTask?.value
    await oldGate.finish(with: fixtureImage())
    await oldTask.value
    #expect(view.image === placeholder)
    await imageGate.finish(with: fixtureImage())
    await view.imageLoading.waitForManagedLoad()
}

@MainActor
@Test func `SwiftUI forwards repeated updates without replacing the same placeholder`() async throws {
    let gate = ImageGate()
    let url = URL(string: "https://example.com/a")!
    let host = UIHostingController(rootView: VulpUI.AsyncImage(url: url, placeholder: PlaceholderAsset(id: "a") { await gate.image() }).frame(width: 0, height: 0))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    window.addSubview(host.view)
    host.view.layoutIfNeeded()
    let view = try #require(findImageView(in: host.view))
    await gate.waitForStart()
    let task = try #require(view.placeholderLoading.task)
    host.rootView = VulpUI.AsyncImage(url: url, contentMode: .fill, placeholder: PlaceholderAsset(id: "a") { nil }).frame(width: 0, height: 0)
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    #expect(view.contentMode == .scaleAspectFill)
    #expect(view.placeholderLoading.task == task)
    let image = fixtureImage()
    await gate.finish(with: image)
    await task.value
    #expect(view.image === image)
}

@MainActor
@Test(arguments: [true, false])
func `Placeholder configuration is independent of async image loading`(configureBeforeLoad: Bool) async throws {
    let gate = ImageGate()
    let view = AsyncImageView()
    let placeholder = fixtureImage()
    if configureBeforeLoad {
        view.setPlaceholder(PlaceholderAsset(id: "placeholder") { placeholder })
        await view.placeholderLoading.task?.value
    }
    let load = Task {
        try await view.loadImage(asset: DataMediaAsset(data: Data(), uniqueKey: "independent"), using: GatedLoader(gate: gate), targetSize: CGSize(width: 40, height: 40))
    }
    await gate.waitForStart()
    if !configureBeforeLoad {
        view.setPlaceholder(PlaceholderAsset(id: "placeholder") { placeholder })
        await view.placeholderLoading.task?.value
    }
    #expect(view.image === placeholder)
    let image = fixtureImage()
    await gate.finish(with: image)
    try await load.value
    #expect(view.image === image)
}

@MainActor
@Test func `Placeholder configured over a loaded image applies to the next source`() async throws {
    let gate = ImageGate()
    let view = AsyncImageView()
    let loader = GatedLoader(gate: gate)
    let first = Task {
        try await view.loadImage(asset: DataMediaAsset(data: Data(), uniqueKey: "first"), using: loader, targetSize: CGSize(width: 40, height: 40))
    }
    await gate.waitForStart()
    let firstImage = fixtureImage()
    await gate.finish(with: firstImage)
    try await first.value
    let placeholder = fixtureImage()
    view.setPlaceholder(PlaceholderAsset(id: "next") { placeholder })
    #expect(view.image === firstImage)
    #expect(view.placeholderLoading.task == nil)
    let second = Task {
        try await view.loadImage(asset: DataMediaAsset(data: Data(), uniqueKey: "second"), using: loader, targetSize: CGSize(width: 40, height: 40))
    }
    await gate.waitForStart(2)
    await view.placeholderLoading.task?.value
    #expect(view.image === placeholder)
    let secondImage = fixtureImage()
    await gate.finish(2, with: secondImage)
    try await second.value
    #expect(view.image === secondImage)
}

@MainActor
@Test func `Completing one load does not clear a replacement started by its callback`() async throws {
    let loading = ImageContentLoading()
    let firstGate = ImageGate()
    let secondGate = ImageGate()
    let firstImage = fixtureImage()
    let secondImage = fixtureImage()
    var displayedImage: CGImage?
    loading.start({
        _ = await firstGate.image()
        return .still(firstImage)
    }, onResult: { result in
        if case .success = result {
            loading.start({
                _ = await secondGate.image()
                return .still(secondImage)
            }, onResult: { result in
                if case .success(.still(let image)) = result { displayedImage = image }
            })
        }
    })
    await firstGate.waitForStart()
    await firstGate.finish(with: firstImage)
    await secondGate.waitForStart()
    #expect(loading.hasManagedLoad)
    await secondGate.finish(with: secondImage)
    await loading.waitForManagedLoad()
    #expect(displayedImage === secondImage)
    #expect(!loading.hasManagedLoad)
}

@MainActor
@Test func `Placeholder configuration while detached waits for reattachment`() async throws {
    let gate = ImageGate()
    let view = AsyncImageView()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    window.addSubview(view)
    view.removeFromSuperview()
    view.setPlaceholder(PlaceholderAsset(id: "detached") { await gate.image() })
    #expect(view.placeholderLoading.task == nil)
    window.addSubview(view)
    await gate.waitForStart()
    let task = view.placeholderLoading.task
    let image = fixtureImage()
    await gate.finish(with: image)
    await task?.value
    #expect(view.image === image)
}

@MainActor
@Test func `Assigning the placeholder image as real content changes its presentation role`() async throws {
    let image = fixtureImage()
    let view = AsyncImageView()
    view.setPlaceholder(PlaceholderAsset(id: "placeholder-17") { image })
    await view.placeholderLoading.task?.value
    #expect(view.image === image)
    view.image = image
    view.setPlaceholder(nil)
    #expect(view.image === image)
}

@MainActor
@Test func `Clearing the placeholder asset rejects pending output and allows the same asset again`() async throws {
    let gate = ImageGate()
    let view = AsyncImageView()
    let asset = PlaceholderAsset(id: "reusable") { await gate.image() }
    view.setPlaceholder(asset)
    await gate.waitForStart()
    let oldTask = view.placeholderLoading.task
    view.setPlaceholder(nil)
    #expect(view.placeholderLoading.task == nil)
    await gate.finish(with: fixtureImage())
    await oldTask?.value
    #expect(view.image == nil)
    view.setPlaceholder(asset)
    await gate.waitForStart(2)
    let task = view.placeholderLoading.task
    let image = fixtureImage()
    await gate.finish(2, with: image)
    await task?.value
    #expect(view.image === image)
}
#endif
