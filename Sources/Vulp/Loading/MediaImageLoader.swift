import Foundation
import CoreGraphics

public protocol MediaImageLoading: Sendable {
    @concurrent
    func load<Request: MediaImageRequestProtocol>(_ request: Request) async throws -> MediaImage

    @concurrent
    func load<Request: MediaImageRequestProtocol>(
        _ request: Request,
        priority: TaskPriority
    ) async throws -> MediaImage

    func prefetch(
        _ asset: any MediaAsset,
        priority: TaskPriority
    ) -> Task<Void, Never>
}

public extension MediaImageLoading {
    /// Loads a request from a task created at the supplied scheduling priority.
    ///
    /// Conforming loaders may provide a more direct implementation. The default
    /// keeps existing custom loaders source-compatible.
    @concurrent
    func load<Request: MediaImageRequestProtocol>(
        _ request: Request,
        priority: TaskPriority
    ) async throws -> MediaImage {
        let task = Task(priority: priority) {
            try await load(request)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Starts a low-priority asset prefetch.
    ///
    /// The default implementation loads a zero-sized image request. Loaders that
    /// cache encoded source data separately can override this to avoid decoding.
    func prefetch(
        _ asset: any MediaAsset,
        priority: TaskPriority = .background
    ) -> Task<Void, Never> {
        let task = Task(priority: priority) { [self] in
            do {
                let request = try MediaImageRequest(assetHandle: asset, targetSize: .zero)
                _ = try await load(request, priority: priority)
            } catch is CancellationError {
                // Cancellation is expected when a prefetched item leaves the
                // collection's visible prefetch window.
            } catch {
                // A visible load can retry and report the failure to the UI.
            }
        }
        return task
    }
}

/// Manages URL prefetch tasks for a changing prefetch window.
///
/// Starting an already-prefetched URL is a no-op. Stop URLs when they leave
/// the window; completed tasks are removed automatically.
public actor MediaImagePrefetcher {
    private struct Entry: Sendable {
        let id: UUID
        let task: Task<Void, Never>
    }

    private let loader: any MediaImageLoading
    private var tasks: [URL: Entry] = [:]

    public init(loader: any MediaImageLoading = MediaImageLoader.default) {
        self.loader = loader
    }

    /// Starts low-priority prefetches for URLs that are not already in flight.
    public func startPrefetching(with urls: [URL]) {
        for url in urls where tasks[url] == nil {
            let id = UUID()
            let task = loader.prefetch(RemoteMediaAsset(url: url), priority: .background)
            tasks[url] = Entry(id: id, task: task)
            Task {
                await task.value
                finishedPrefetching(url, id: id)
            }
        }
    }

    /// Cancels the prefetch waiters for URLs that left the window.
    public func stopPrefetching(with urls: [URL]) {
        for url in urls {
            tasks.removeValue(forKey: url)?.task.cancel()
        }
    }

    /// Cancels all prefetch waiters managed by this prefetcher.
    public func stopPrefetching() {
        let activeTasks = tasks.values.map(\.task)
        tasks.removeAll(keepingCapacity: false)
        activeTasks.forEach { $0.cancel() }
    }

    private func finishedPrefetching(_ url: URL, id: UUID) {
        guard tasks[url]?.id == id else { return }
        tasks.removeValue(forKey: url)
    }
}

public typealias ImageLoading = MediaImageLoading
