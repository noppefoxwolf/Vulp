import Foundation

/// Statically composes the still/sequence image decoder with a direct-URL video decoder.
public struct MediaImageDecoderSet<ImageDecoder: MediaImageDecoding, VideoDecoder: VideoFrameDecoding>: MediaImageDecoding {
    private let imageDecoder: ImageDecoder
    private let videoDecoder: VideoDecoder

    public init(imageDecoder: ImageDecoder, videoDecoder: VideoDecoder) {
        self.imageDecoder = imageDecoder
        self.videoDecoder = videoDecoder
    }

    @concurrent
    public func deserialize(_ data: Data) async throws -> MediaImage {
        try await imageDecoder.deserialize(data)
    }

    @concurrent
    public func deserialize(_ data: Data, options: ImageDecodingOptions) async throws -> MediaImage {
        try await imageDecoder.deserialize(data, options: options)
    }

    @concurrent
    public func deserialize(
        _ data: Data,
        options: ImageDecodingOptions,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        try await imageDecoder.deserialize(data, options: options, maximumPixelDimension: maximumPixelDimension)
    }

    @concurrent
    public func decodeVideoFrame(
        from url: URL,
        at time: TimeInterval,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        try await videoDecoder.decodeFrame(from: url, at: time, maximumPixelDimension: maximumPixelDimension)
    }

}

extension MediaImageDecoderSet: MediaImageSequenceDecoding where ImageDecoder: MediaImageSequenceDecoding {
    @concurrent
    public func frameCount(in data: Data) async throws -> Int {
        try await imageDecoder.frameCount(in: data)
    }

    @concurrent
    public func frameDurations(in data: Data) async throws -> [TimeInterval] {
        try await imageDecoder.frameDurations(in: data)
    }
}
