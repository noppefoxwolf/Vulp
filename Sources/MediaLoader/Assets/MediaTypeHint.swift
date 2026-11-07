import Foundation
import UniformTypeIdentifiers

/// A format hint supplied by a caller or inferred from the source URL.
public enum MediaTypeHint: Hashable, Sendable {
    case image
    case video
}

enum MediaSourceResolver {
    static func resolution(for asset: any MediaAsset) -> MediaSourceResolution {
        guard let url = asset.directURL else { return .imageData }
        let inferredType = mediaType(for: url)

        if let inferredType, let hint = asset.mediaTypeHint, inferredType != hint {
            return .probeVideoURL(url)
        }
        if inferredType == .video || asset.mediaTypeHint == .video {
            return .videoURL(url)
        }
        if inferredType == .image { return .imageData }
        return .probeVideoURL(url)
    }

    private static func mediaType(for url: URL) -> MediaTypeHint? {
        guard !url.pathExtension.isEmpty,
              let type = UTType(filenameExtension: url.pathExtension.lowercased())
        else { return nil }

        if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent) {
            return .video
        }
        if type.conforms(to: .image) {
            return .image
        }
        return nil
    }
}

enum MediaSourceResolution {
    case imageData
    case videoURL(URL)
    case probeVideoURL(URL)
}
