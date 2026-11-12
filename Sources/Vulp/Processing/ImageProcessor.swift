import Foundation

public protocol ImageProcessor: Sendable {
    @concurrent
    func process<Request: MediaImageRequestProtocol>(_ image: MediaImage, for request: Request) async throws -> MediaImage
}

public extension ImageProcessor {
    /// Chains this processor with another processor, applying this processor first.
    func then<Next: ImageProcessor>(_ next: Next) -> ImageProcessorChain<Self, Next> {
        ImageProcessorChain(first: self, then: next)
    }
}
