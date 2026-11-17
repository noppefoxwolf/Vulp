#if canImport(UIKit)
import UIKit

/// Coordinates managed and caller-owned image loads without exposing tasks or generations.
@MainActor
final class ImageContentLoading {
    private var task: Task<Void, Never>?
    private var generation = UUID()

    var hasManagedLoad: Bool { task != nil }

    /// Starts work owned by the view. Superseded results never reach the callback.
    func start(
        _ operation: @escaping @MainActor @Sendable () async throws -> ImageLoadingResult,
        onResult: @escaping @MainActor (Result<ImageLoadingResult, any Error>) -> Void
    ) {
        invalidate()
        let generation = generation
        task = Task { [weak self] in
            defer {
                if let self, self.generation == generation { self.task = nil }
            }
            do {
                try Task.checkCancellation()
                let content = try await operation()
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                onResult(.success(content))
            } catch {
                guard let self, self.generation == generation else { return }
                onResult(.failure(error))
            }
        }
    }

    /// Performs work in the calling task. Detachment does not invalidate this load.
    /// Result delivery and validity checking run together, without another suspension.
    /// Finish notification runs only while this operation is still current.
    func load(
        _ operation: @MainActor @Sendable () async throws -> ImageLoadingResult,
        onSuccess: @MainActor (ImageLoadingResult) -> Void,
        onFinish: @MainActor () -> Void
    ) async throws {
        invalidate()
        let generation = generation
        defer {
            if self.generation == generation { onFinish() }
        }
        let content = try await operation()
        try Task.checkCancellation()
        guard self.generation == generation else { throw CancellationError() }
        onSuccess(content)
    }

    /// Supersedes both managed and caller-owned work.
    func invalidate() {
        generation = UUID()
        task?.cancel()
        task = nil
    }

    /// Stops only view-owned work, preserving any caller-owned async load.
    func cancelManagedLoad() {
        guard task != nil else { return }
        invalidate()
    }

    /// Waits for the currently managed load without exposing its task handle.
    func waitForManagedLoad() async {
        await task?.value
    }

    isolated deinit {
        task?.cancel()
    }
}
#endif
