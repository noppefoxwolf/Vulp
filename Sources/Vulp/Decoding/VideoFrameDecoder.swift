import Foundation

public protocol VideoFrameDecoding: MediaImageDecoding {
    /// Returns whether this decoder can extract a frame directly from the URL.
    @concurrent
    func canDecode(url: URL) async -> Bool

    @concurrent
    func decodeFrame(
        from url: URL,
        at time: TimeInterval,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage
}

public extension VideoFrameDecoding {
    @concurrent
    func deserialize(_ data: Data) async throws -> MediaImage {
        throw MediaImageDecodingError.unsupportedSource
    }

    @concurrent
    func decodeVideoFrame(
        from url: URL,
        at time: TimeInterval,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        try await decodeFrame(from: url, at: time, maximumPixelDimension: maximumPixelDimension)
    }
}
