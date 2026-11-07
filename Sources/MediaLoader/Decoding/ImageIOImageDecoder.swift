import Foundation
import ImageIO

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct ImageIOImageDecoder: MediaImageSequenceDecoding {
    public init() {}

    @concurrent
    public func deserialize(_ data: Data) async throws -> MediaImage {
        try await deserialize(data, options: .firstFrame)
    }

    @concurrent
    public func deserialize(_ data: Data, options: ImageDecodingOptions) async throws -> MediaImage {
        try await deserialize(data, options: options, maximumPixelDimension: nil)
    }

    @concurrent
    public func deserialize(
        _ data: Data,
        options: ImageDecodingOptions,
        maximumPixelDimension: Int?
    ) async throws -> MediaImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageDeserializationError.invalidData
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
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            ]
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions as CFDictionary)
        } else {
            cgImage = CGImageSourceCreateImageAtIndex(source, index, nil)
        }
        guard let cgImage else {
            throw ImageDeserializationError.invalidData
        }

        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        #else
        throw ImageDeserializationError.invalidData
        #endif
    }

    @concurrent
    public func frameCount(in data: Data) async throws -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageDeserializationError.invalidData
        }
        return CGImageSourceGetCount(source)
    }

    @concurrent
    public func frameDurations(in data: Data) async throws -> [TimeInterval] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageDeserializationError.invalidData
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

public typealias ImageIOImageDeserializer = ImageIOImageDecoder
