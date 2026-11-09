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

#if canImport(AVFoundation)
import AVFoundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Generates a thumbnail from a video URL without first downloading the complete asset.
public struct AVFoundationVideoFrameDecoder: VideoFrameDecoding {
    public init() {}

    @concurrent
    public func canDecode(data: Data) async -> Bool { false }

    @concurrent
    public func canDecode(url: URL) async -> Bool {
        guard !url.pathExtension.isEmpty,
              let type = UTType(filenameExtension: url.pathExtension.lowercased())
        else { return true }

        if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent) {
            return true
        }
        if type.conforms(to: .image) { return false }
        // Unknown extensions still get one direct AVFoundation attempt.
        return true
    }

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
