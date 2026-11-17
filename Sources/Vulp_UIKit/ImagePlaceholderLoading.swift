#if canImport(UIKit)
import UIKit
import Vulp

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
    private var placeholder: ImagePlaceholder?
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

    func setPlaceholder(
        _ placeholder: ImagePlaceholder?,
        onImage: @escaping @MainActor (CGImage?) -> Void
    ) {
        guard self.placeholder?.id != placeholder?.id else { return }
        clearPlaceholder()
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
                let image = try await placeholder.image()
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

    /// Invalidates the previous source's work while retaining the configured placeholder.
    func resetGeneration() {
        cancelGeneration()
        state = .ready
    }

    /// Cancels in-flight work while preserving the placeholder and any finished state.
    func cancelGeneration() {
        generation = UUID()
        if case .generating(let task) = state {
            task.cancel()
            state = .ready
        }
    }

    /// Cancels generation and removes the configured placeholder and delivery callback.
    func clearPlaceholder() {
        cancelGeneration()
        placeholder = nil
        onImage = nil
        state = .ready
    }

    isolated deinit {
        task?.cancel()
    }
}
#endif
