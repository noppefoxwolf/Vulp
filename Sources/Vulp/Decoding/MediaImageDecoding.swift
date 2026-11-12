import Foundation

public protocol MediaImageDecoding: Sendable {
    // Source recognition
    /// Quickly checks whether this decoder can handle a local source file URL.
    @concurrent
    func canDecode(url: URL) async -> Bool

    // Image decoding
    /// Decodes an image from a local source file, such as the first frame of a video.
    @concurrent
    func decode(
        from url: URL,
        options: ImageDecodingOptions,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage

    // Animated sequence inspection
    /// Returns whether this decoder can inspect and load an animated image sequence.
    @concurrent
    func canDecodeSequence(data: Data) async -> Bool

    @concurrent
    func frameCount(in data: Data) async throws -> Int

    @concurrent
    func frameDurations(in data: Data) async throws -> [TimeInterval]
}

public extension MediaImageDecoding {
    @concurrent
    func canDecodeSequence(data: Data) async -> Bool { false }

    @concurrent
    func frameCount(in data: Data) async throws -> Int {
        throw MediaImageDecodingError.unsupportedSource
    }

    @concurrent
    func frameDurations(in data: Data) async throws -> [TimeInterval] {
        Array(repeating: 0.1, count: try await frameCount(in: data))
    }
}

public enum ImageDecodingOptions: Hashable, Sendable {
    /// Selects the first image frame, or the video frame at time zero.
    case firstFrame
    /// Selects an indexed frame from an animated image. Video timestamps are not frame indices.
    case frame(index: Int)
}

public enum ImageDecodingError: Error, Equatable {
    case invalidData
    case frameSelectionUnsupported(Int)
}

public enum MediaImageDecodingError: Error, Equatable {
    case unsupportedSource
    case videoFrameIndexUnsupported(Int)
}
