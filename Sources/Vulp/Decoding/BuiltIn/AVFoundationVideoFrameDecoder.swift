import Foundation

#if canImport(AVFoundation)
import AVFoundation
/// Generates a thumbnail from a local source file managed by the asset data cache.
public struct AVFoundationVideoFrameDecoder: MediaImageDecoding {
    public init() {}

    @concurrent
    public func canDecode(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.load(.tracks) else { return false }
        return tracks.contains(where: { $0.mediaType == .video })
    }

    @concurrent
    public func decode(
        from url: URL,
        options: ImageDecodingOptions,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        if case .frame(let index) = options {
            throw MediaImageDecodingError.videoFrameIndexUnsupported(index)
        }
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.load(.tracks)
        } catch let error as AVError where error.code == .fileFormatNotRecognized {
            throw MediaImageDecodingError.unsupportedSource
        }
        guard tracks.contains(where: { $0.mediaType == .video }) else {
            throw MediaImageDecodingError.unsupportedSource
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let maximumPixelDimension, maximumPixelDimension > 0 {
            generator.maximumSize = CGSize(width: maximumPixelDimension, height: maximumPixelDimension)
        }
        let (cgImage, _) = try await generator.image(at: .zero)

        return cgImage
    }
}
#endif
