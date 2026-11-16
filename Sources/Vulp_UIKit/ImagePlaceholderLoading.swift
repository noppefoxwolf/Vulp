#if canImport(UIKit)
import UIKit

/// Owns placeholder generation and rejects results from superseded loads.
@MainActor
final class ImagePlaceholderLoading {
    private(set) var task: Task<Void, Never>?
    private var generation = UUID()
    private var placeholder: (@Sendable () async throws -> CGImage?)?
    private var onImage: (@MainActor (CGImage?) -> Void)?

    func configure(
        _ placeholder: (@Sendable () async throws -> CGImage?)?,
        onImage: @escaping @MainActor (CGImage?) -> Void
    ) {
        cancel()
        self.placeholder = placeholder
        self.onImage = onImage
    }

    func resume() {
        guard task == nil, let placeholder, let onImage else { return }
        let generation = generation
        task = Task { [weak self] in
            do {
                let image = try await Self.generate(placeholder)
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                self.cancel()
                onImage(image)
            } catch {
                guard let self, self.generation == generation else { return }
                // A failed placeholder is not retried on every layout pass.
                self.cancel()
            }
        }
    }

    /// Keeps the provider so an interrupted generation can resume on reattachment.
    func suspend() {
        generation = UUID()
        task?.cancel()
        task = nil
    }

    func cancel() {
        suspend()
        placeholder = nil
        onImage = nil
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
