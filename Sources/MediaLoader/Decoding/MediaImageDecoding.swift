import Foundation

public protocol MediaImageDecoding: Sendable {
    @concurrent
    func deserialize(_ data: Data) async throws -> MediaImage

    @concurrent
    func deserialize(_ data: Data, options: ImageDecodingOptions) async throws -> MediaImage

    /// Decodes an image with an optional limit on its longest pixel dimension.
    /// This is a decode-time memory/CPU bound; the processor still controls the final output size.
    @concurrent
    func deserialize(
        _ data: Data,
        options: ImageDecodingOptions,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage

    /// Generates the default thumbnail frame directly from a video URL.
    @concurrent
    func decodeVideoFrame(
        from url: URL,
        at time: TimeInterval,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage
}

public typealias ImageDeserializer = MediaImageDecoding

public extension MediaImageDecoding {
    @concurrent
    func deserialize(_ data: Data, options: ImageDecodingOptions) async throws -> MediaImage {
        switch options {
        case .firstFrame:
            try await deserialize(data)
        case .frame(let index):
            throw ImageDeserializationError.frameSelectionUnsupported(index)
        }
    }

    /// Custom deserializers that do not support downsampling retain their existing decode behavior.
    @concurrent
    func deserialize(
        _ data: Data,
        options: ImageDecodingOptions,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        try await deserialize(data, options: options)
    }

    @concurrent
    func decodeVideoFrame(
        from url: URL,
        at time: TimeInterval,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        throw MediaImageDecodingError.unsupportedSource
    }
}

public protocol MediaImageSequenceDecoding: MediaImageDecoding {
    @concurrent
    func frameCount(in data: Data) async throws -> Int

    @concurrent
    func frameDurations(in data: Data) async throws -> [TimeInterval]
}

public typealias ImageSequenceDeserializer = MediaImageSequenceDecoding

public extension MediaImageSequenceDecoding {
    @concurrent
    func frameDurations(in data: Data) async throws -> [TimeInterval] {
        Array(repeating: 0.1, count: try await frameCount(in: data))
    }
}

public enum ImageDecodingOptions: Hashable, Sendable {
    case firstFrame
    case frame(index: Int)
}

public enum ImageDeserializationError: Error, Equatable {
    case invalidData
    case frameSelectionUnsupported(Int)
}

public enum MediaImageDecodingError: Error, Equatable {
    case unsupportedSource
    case videoFrameIndexUnsupported(Int)
}
