#if canImport(UIKit)
import UIKit

/// Owns placeholder generation and rejects results from superseded loads.
@MainActor
final class ImagePlaceholderLoading {
    private(set) var task: Task<Void, Never>?
    private var generation = UUID()
    private var didFinish = false
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
        guard !didFinish, task == nil, let placeholder, let onImage else { return }
        let generation = generation
        task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let image = try await Self.generate(placeholder)
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                self.finish()
                onImage(image)
            } catch {
                guard let self, self.generation == generation else { return }
                // A failed placeholder is not retried on every layout pass.
                self.finish()
            }
        }
    }

    private func finish() {
        task = nil
        didFinish = true
    }

    /// Invalidates the previous source's work while retaining the configured provider.
    func restart() {
        suspend()
        didFinish = false
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
        didFinish = false
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
