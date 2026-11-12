import Foundation

/// Runs two image processors in sequence, passing the first processor's output to the second.
private struct ImageProcessorChain<First: ImageProcessor, Second: ImageProcessor>: ImageProcessor {
    private let first: First
    private let second: Second

    init(first: First, then second: Second) {
        self.first = first
        self.second = second
    }

    @concurrent
    func process<Request: MediaImageRequestProtocol>(
        _ image: MediaImage,
        for request: Request
    ) async throws -> MediaImage {
        let intermediate = try await first.process(image, for: request)
        return try await second.process(intermediate, for: request)
    }
}

/// Composes two image processors, applying the left-hand processor first.
public func +<First: ImageProcessor, Second: ImageProcessor>(
    lhs: First,
    rhs: Second
) -> some ImageProcessor {
    ImageProcessorChain(first: lhs, then: rhs)
}
