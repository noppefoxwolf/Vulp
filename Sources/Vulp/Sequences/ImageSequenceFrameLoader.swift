import Foundation

/// Loads the requested sequence frame and keeps a bounded set of nearby frames ready.
public actor ImageSequenceFrameLoader<Loader: MediaImageLoading> {
    private let sequence: ImageSequence
    private let loader: Loader
    private let targetSize: CGSize
    private let resizeMode: ImageResizeMode
    private let prefetchCount: Int
    private let playbackFrameIndices: [Int]?
    private var frameTasks: [Int: Task<MediaImage, any Error>] = [:]

    public init(
        sequence: ImageSequence,
        using loader: Loader,
        targetSize: CGSize,
        resizeMode: ImageResizeMode = .fit,
        prefetchCount: Int = 3,
        playbackFrameIndices: [Int]? = nil
    ) {
        self.sequence = sequence
        self.loader = loader
        self.targetSize = targetSize
        self.resizeMode = resizeMode
        self.prefetchCount = max(0, prefetchCount)
        self.playbackFrameIndices = playbackFrameIndices
    }

    /// Returns one frame and starts loading up to `prefetchCount` following frames.
    public func frame(at index: Int) async throws -> MediaImage {
        guard index >= 0, index < sequence.frameCount else {
            throw ImageSequenceError.invalidFrameIndex(index)
        }

        let window = frameWindow(startingAt: index)
        discardFrames(outside: Set(window))
        for frameIndex in window {
            try schedule(frameIndex)
        }

        guard let task = frameTasks[index] else {
            throw CancellationError()
        }

        do {
            return try await task.value
        } catch {
            frameTasks[index] = nil
            throw error
        }
    }

    /// Cancels pending frame work and releases the loader's retained frame window.
    public func cancel() {
        for task in frameTasks.values {
            task.cancel()
        }
        frameTasks.removeAll()
    }

    func frameWindow(startingAt index: Int) -> [Int] {
        guard sequence.frameCount > 0 else { return [] }
        if let playbackFrameIndices,
           let playbackPosition = playbackFrameIndices.firstIndex(of: index) {
            guard prefetchCount > 0 else { return [index] }
            var window = [index]
            var included = Set(window)
            for offset in 1..<playbackFrameIndices.count {
                let candidate = playbackFrameIndices[(playbackPosition + offset) % playbackFrameIndices.count]
                guard included.insert(candidate).inserted else { continue }
                window.append(candidate)
                if window.count >= prefetchCount + 1 { break }
            }
            return window
        }

        let count = min(prefetchCount, sequence.frameCount - 1) + 1
        return (0..<count).map { (index + $0) % sequence.frameCount }
    }

    private func discardFrames(outside window: Set<Int>) {
        let discardedIndices = frameTasks.keys.filter { !window.contains($0) }
        for index in discardedIndices {
            frameTasks[index]?.cancel()
            frameTasks[index] = nil
        }
    }

    private func schedule(_ index: Int) throws {
        guard frameTasks[index] == nil else { return }
        let request = try sequence.frameRequest(at: index, targetSize: targetSize, resizeMode: resizeMode)

        let loader = self.loader
        frameTasks[index] = Task {
            try await loader.load(request)
        }
    }
}
