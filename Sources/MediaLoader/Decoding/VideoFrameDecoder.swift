import Foundation

public protocol VideoFrameDecoding: Sendable {
    @concurrent
    func decodeFrame(
        from url: URL,
        at time: TimeInterval,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage
}

#if canImport(AVFoundation)
import AVFoundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Generates a thumbnail from a video URL without first downloading the complete asset.
public struct AVFoundationVideoFrameDecoder: VideoFrameDecoding {
    public init() {}

    @concurrent
    public func decodeFrame(
        from url: URL,
        at time: TimeInterval,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
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
        let requestedTime = CMTime(seconds: time, preferredTimescale: 600)
        let (cgImage, _) = try await generator.image(at: requestedTime)

        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        #else
        throw MediaImageDecodingError.unsupportedSource
        #endif
    }
}
#endif
