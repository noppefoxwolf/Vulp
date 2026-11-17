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

    enum ActivityState {
        case active
        case inactive
    }

    private var state: State = .ready
    private var generation = UUID()
    private var placeholder: (@Sendable () async throws -> CGImage?)?
    private var onImage: (@MainActor (CGImage?) -> Void)?

    /// Inactive generation is cancelled; becoming active does not start work automatically.
    var activityState: ActivityState = .active {
        didSet {
            if activityState == .inactive { cancelGeneration() }
        }
    }

    var task: Task<Void, Never>? {
        if case .generating(let task) = state { task } else { nil }
    }

    func setProvider(
        _ placeholder: (@Sendable () async throws -> CGImage?)?,
        onImage: @escaping @MainActor (CGImage?) -> Void
    ) {
        clearProvider()
        self.placeholder = placeholder
        self.onImage = onImage
    }

    func startIfNeeded() {
        guard case .ready = state, activityState == .active,
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
    func resetGeneration() {
        cancelGeneration()
        state = .ready
    }

    /// Cancels in-flight work while preserving the provider and any finished state.
    func cancelGeneration() {
        generation = UUID()
        if case .generating(let task) = state {
            task.cancel()
            state = .ready
        }
    }

    /// Cancels generation and removes the configured provider and delivery callback.
    func clearProvider() {
        cancelGeneration()
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
