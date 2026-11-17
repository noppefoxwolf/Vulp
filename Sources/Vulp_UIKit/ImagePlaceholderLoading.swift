#if canImport(UIKit)
import UIKit

/// Owns placeholder generation and rejects results from superseded loads.
@MainActor
final class ImagePlaceholderLoading {
    private enum State {
        case ready
        case generating(Task<Void, Never>)
        case finished
    }

    private enum Attachment {
        case active
        case detached
    }

    private var state: State = .ready
    private var attachment: Attachment = .active
    private var generation = UUID()
    private var placeholder: (@Sendable () async throws -> CGImage?)?
    private var onImage: (@MainActor (CGImage?) -> Void)?

    var task: Task<Void, Never>? {
        if case .generating(let task) = state { task } else { nil }
    }

    func configure(
        _ placeholder: (@Sendable () async throws -> CGImage?)?,
        onImage: @escaping @MainActor (CGImage?) -> Void
    ) {
        cancel()
        self.placeholder = placeholder
        self.onImage = onImage
    }

    func resume() {
        guard case .ready = state, attachment == .active,
              let placeholder, let onImage else { return }
        let generation = generation
        state = .generating(Task { [weak self] in
            do {
                try Task.checkCancellation()
                let image = try await Self.generate(placeholder)
                try Task.checkCancellation()
                guard let self, self.generation == generation else { return }
                self.state = .finished
                onImage(image)
            } catch {
                guard let self, self.generation == generation else { return }
                // A failed placeholder is not retried on every layout pass.
                self.state = .finished
            }
        })
    }

    /// Invalidates the previous source's work while retaining the configured provider.
    func restart() {
        suspend()
        state = .ready
    }

    /// Keeps the provider so an interrupted generation can resume on reattachment.
    func suspend() {
        generation = UUID()
        if case .generating(let task) = state {
            task.cancel()
            state = .ready
        }
    }

    func detach() {
        attachment = .detached
        suspend()
    }

    /// Re-enables generation; the view decides whether a placeholder should be displayed.
    func attach() {
        attachment = .active
    }

    func cancel() {
        suspend()
        placeholder = nil
        onImage = nil
        state = .ready
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
