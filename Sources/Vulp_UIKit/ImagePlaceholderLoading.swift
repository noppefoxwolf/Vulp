#if canImport(UIKit)
import UIKit

/// Owns placeholder generation and rejects results from superseded loads.
@MainActor
final class ImagePlaceholderLoading {
    private var task: Task<Void, Never>?
    private(set) var generation = UUID()

    func start(
        _ placeholder: (@Sendable () async throws -> CGImage?)?,
        onImage: @escaping @MainActor (CGImage?) -> Void
    ) {
        guard let placeholder else { return }
        let generation = generation
        task = Task { [weak self] in
            do {
                let image = try await Self.generate(placeholder)
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                onImage(image)
            } catch {
                // Placeholder failure must not fail the image request.
            }
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
    }

    isolated deinit {
        task?.cancel()
    }

    @concurrent
    private static func generate(
        _ placeholder: @Sendable () async throws -> CGImage?
    ) async throws -> CGImage? {
        try await placeholder()
    }
}
#endif
