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

public typealias ImageLoading = MediaImageLoading
