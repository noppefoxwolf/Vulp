import Foundation

#if canImport(AVFoundation)
import AVFoundation
/// Generates a thumbnail from a local source file managed by the asset data cache.
public struct AVFoundationVideoFrameDecoder: MediaImageDecoding {
    public init() {}

    @concurrent
    public func canDecode(url: URL) async -> Bool {
        guard let mimeType = videoMIMEType(for: url) else { return false }
        let asset = AVURLAsset(url: url, options: [AVURLAssetOverrideMIMETypeKey: mimeType])
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
        guard let mimeType = videoMIMEType(for: url) else {
            throw MediaImageDecodingError.unsupportedSource
        }
        let asset = AVURLAsset(url: url, options: [AVURLAssetOverrideMIMETypeKey: mimeType])
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

    private func videoMIMEType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "3gp", "3g2":
            return "video/3gpp"
        default:
            guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? file.close() }
            guard let header = try? file.read(upToCount: 12),
                  header.count >= 8,
                  String(data: header[4..<8], encoding: .ascii) == "ftyp"
            else { return nil }
            return "video/mp4"
        }
    }
}
#endif
