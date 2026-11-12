import Foundation

public protocol ImageProcessor: Sendable {
    @concurrent
    func process<Request: MediaImageRequestProtocol>(_ image: MediaImage, for request: Request) async throws -> MediaImage
}
