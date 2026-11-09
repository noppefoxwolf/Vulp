import Foundation

public enum ImageSequenceError: Error, Equatable {
    case invalidFrameIndex(Int)
    case unsupportedMediaSource
}

/// Encoded image data with a stable identity and a known number of frames.
public struct ImageSequence: Sendable {
    public let identifier: String
    public let frameCount: Int
    public let frameDurations: [TimeInterval]
    private let data: Data

    init(identifier: String, data: Data, frameDurations: [TimeInterval]) {
        self.identifier = identifier
        self.data = data
        self.frameDurations = frameDurations
        self.frameCount = frameDurations.count
    }

    /// Selects the supported display rate and source frames for the requested fidelity.
    @concurrent
    public func playbackPlan(levelOfIntegrity: Double = 1) async -> ImageSequencePlaybackPlan {
        ImageSequencePlaybackPlan(frameDurations: frameDurations, levelOfIntegrity: levelOfIntegrity)
    }

    /// Creates a cacheable request for one frame in this sequence.
    public func frameRequest(
        at index: Int,
        targetSize: CGSize,
        renderingMode: ImageRenderingMode = .original
    ) throws -> MediaImageRequest {
        guard index >= 0, index < frameCount else {
            throw ImageSequenceError.invalidFrameIndex(index)
        }

        let asset = DataMediaAsset(data: data, uniqueKey: identifier)
        return try MediaImageRequest(
            assetHandle: asset,
            targetSize: targetSize,
            renderingMode: renderingMode,
            decodingOptions: .frame(index: index)
        )
    }

    /// Loads and decodes every frame through the regular image cache pipeline.
    @concurrent
    public func loadFrames<Loader: MediaImageLoading>(
        using loader: Loader,
        targetSize: CGSize
    ) async throws -> [MediaImage] {
        var images: [MediaImage] = []
        images.reserveCapacity(frameCount)
        for index in 0..<frameCount {
            try Task.checkCancellation()
            let request = try frameRequest(at: index, targetSize: targetSize)
            images.append(try await loader.load(request))
        }
        return images
    }
}

public protocol MediaImageSequenceLoading: MediaImageLoading {
    @concurrent
    func loadSequence(from asset: any MediaAsset) async throws -> ImageSequence
}

public typealias ImageSequenceLoading = MediaImageSequenceLoading

public extension MediaImageSequenceDecoding {
    @concurrent
    func loadSequence(_ data: Data, identifier: String) async throws -> ImageSequence {
        let durations = try await frameDurations(in: data)
        return ImageSequence(identifier: identifier, data: data, frameDurations: durations)
    }
}
