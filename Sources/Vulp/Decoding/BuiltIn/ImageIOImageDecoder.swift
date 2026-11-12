import Foundation
import ImageIO

public struct ImageIOImageDecoder: MediaImageDecoding {
    public init() {}

    @concurrent
    public func canDecode(url: URL) async -> Bool {
        guard url.isFileURL else { return false }
        return CGImageSourceCreateWithURL(url as CFURL, nil) != nil
    }

    @concurrent
    public func canDecodeSequence(data: Data) async -> Bool {
        CGImageSourceCreateWithData(data as CFData, nil) != nil
    }

    @concurrent
    public func decode(
        from url: URL,
        options: ImageDecodingOptions,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        guard url.isFileURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else {
            throw ImageDecodingError.invalidData
        }
        let index: Int
        switch options {
        case .firstFrame:
            index = 0
        case .frame(let frameIndex):
            guard frameIndex >= 0, frameIndex < CGImageSourceGetCount(source) else {
                throw ImageSequenceError.invalidFrameIndex(frameIndex)
            }
            index = frameIndex
        }

        let cgImage: CGImage?
        if let maximumPixelDimension, maximumPixelDimension > 0 {
            // ImageIO creates a reduced-resolution frame directly, avoiding a full-size decoded bitmap.
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            ]
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions as CFDictionary)
        } else {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 1
            let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 1
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            ]
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
        }
        guard let cgImage else {
            throw ImageDecodingError.invalidData
        }

        return cgImage
    }

    @concurrent
    public func frameCount(in data: Data) async throws -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageDecodingError.invalidData
        }
        return CGImageSourceGetCount(source)
    }

    @concurrent
    public func frameDurations(in data: Data) async throws -> [TimeInterval] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageDecodingError.invalidData
        }

        return (0..<CGImageSourceGetCount(source)).map { index in
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] else {
                return 0.1
            }
            let metadata = properties.values.compactMap { $0 as? [String: Any] }
            let delay = metadata.lazy.compactMap { values -> Double? in
                (values["UnclampedDelayTime"] as? NSNumber)?.doubleValue
                    ?? (values["DelayTime"] as? NSNumber)?.doubleValue
            }.first
            guard let delay, delay.isFinite, delay > 0 else { return 0.1 }
            return max(delay, 0.01)
        }
    }
}
