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
    public func canDecode(data: Data) async -> Bool {
        ImageDataSignature.isRecognized(data)
            || CGImageSourceCreateWithData(data as CFData, nil) != nil
    }

    @concurrent
    public func canDecode(url: URL) async -> Bool { false }

    @concurrent
    public func canDecodeSequence(data: Data) async -> Bool {
        await canDecode(data: data)
    }

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

private enum ImageDataSignature {
    static func isRecognized(_ data: Data) -> Bool {
        let bytes = Array(data.prefix(64))

        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true } // JPEG
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return true } // PNG/APNG
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) { return true }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return true } // TIFF
        if bytes.starts(with: Array("BM".utf8)) { return true } // BMP
        if bytes.starts(with: [0x00, 0x00, 0x01, 0x00]) || bytes.starts(with: [0x00, 0x00, 0x02, 0x00]) { return true } // ICO/CUR
        if bytes.starts(with: Array("icns".utf8)) { return true }
        if bytes.count >= 12,
           bytes.starts(with: Array("RIFF".utf8)),
           Array(bytes[8..<12]) == Array("WEBP".utf8) { return true }
        if bytes.starts(with: [0xFF, 0x0A]) { return true } // JPEG XL codestream
        if bytes.starts(with: [0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A]) { return true } // JPEG XL container
        if bytes.starts(with: [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A]) { return true } // JPEG 2000
        if bytes.starts(with: [0xFF, 0x4F, 0xFF, 0x51]) { return true } // JPEG 2000 codestream
        if bytes.starts(with: [0x59, 0xA6, 0x6A, 0x95]) { return true } // Sun Raster
        if bytes.starts(with: [0x76, 0x2F, 0x31, 0x01]) { return true } // OpenEXR
        if isPortableAnyMap(bytes) { return true }
        return isHEIFOrAVIF(bytes)
    }

    private static func isPortableAnyMap(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 3, bytes[0] == 0x50 else { return false }
        guard (0x31...0x37).contains(bytes[1]) else { return false } // P1 through P7
        return bytes[2] == 0x20 || bytes[2] == 0x09 || bytes[2] == 0x0A || bytes[2] == 0x0D
    }

    private static func isHEIFOrAVIF(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 12,
              Array(bytes[4..<8]) == Array("ftyp".utf8)
        else { return false }

        let supportedBrands: [[UInt8]] = [
            "heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs",
            "mif1", "msf1", "avif", "avis",
        ].map { Array($0.utf8) }
        let brandOffsets = [8] + (bytes.count >= 20 ? Array(stride(from: 16, through: bytes.count - 4, by: 4)) : [])
        return brandOffsets.contains { offset in
            let brand = Array(bytes[offset..<(offset + 4)])
            return supportedBrands.contains(brand)
        }
    }
}
