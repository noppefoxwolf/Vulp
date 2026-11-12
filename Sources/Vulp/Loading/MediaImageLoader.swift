import Foundation
import CoreGraphics

public protocol MediaImageLoading: Sendable {
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
    /// Loads a request at user-initiated priority.
    @concurrent
    func load<Request: MediaImageRequestProtocol>(_ request: Request) async throws -> MediaImage {
        try await load(request, priority: .userInitiated)
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
                let request = try MediaImageRequest(asset: asset, targetSize: .zero)
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
