import VulpUI

struct DemoImageProcessorPipeline<First: ImageProcessor, Second: ImageProcessor>: ImageProcessor {
    private let first: First
    private let second: Second

    init(_ first: First, then second: Second) {
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
