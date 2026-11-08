import CoreGraphics
import Foundation
import Vulp
import Testing

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Test func imageProcessorChainRunsProcessorsInOrder() async throws {
    let source = try await TestImageData.image()
    let asset = DataImageAsset(data: TestImageData.png, uniqueKey: "processor-chain")
    let request = try ImageLoadRequest(assetHandle: asset, targetSize: .zero)
    let recorder = ProcessorCallRecorder()
    let processor = NamedImageProcessor(name: "first", recorder: recorder)
        .then(NamedImageProcessor(name: "second", recorder: recorder))

    let result = try await processor.process(source, for: request)

    #expect(result === source)
    #expect(await recorder.calls == ["first", "second"])
}

@Test func resizeProcessorProducesBucketedPixelSize() async throws {
    let source = try await TestImageData.image()
    let asset = DataImageAsset(data: TestImageData.png, uniqueKey: "fixture")
    let request = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: CGSize(width: 12, height: 8)
    )

    let result = try await ResizeImageProcessor().process(source, for: request)

    #expect(result.pixelWidth == 11)
    #expect(result.pixelHeight == 11)
}

@Test func resizeProcessorFitsWithoutChangingSourceAspectRatio() async throws {
    let source = try processorFixtureImage()
    let asset = DataImageAsset(data: TestImageData.png, uniqueKey: "fit-resize")
    let request = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: CGSize(width: 8, height: 8),
        resizeMode: .fit
    )

    let result = try await ResizeImageProcessor().process(source, for: request)

    #expect(result.pixelWidth == 8)
    #expect(result.pixelHeight == 3)
}

@Test func resizeProcessorFillsAndCenterCropsToRequestedSize() async throws {
    let source = try processorFixtureImage()
    let asset = DataImageAsset(data: TestImageData.png, uniqueKey: "fill-resize")
    let request = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: CGSize(width: 8, height: 8),
        resizeMode: .fill
    )

    let result = try await ResizeImageProcessor().process(source, for: request)

    #expect(result.pixelWidth == 8)
    #expect(result.pixelHeight == 8)
    #expect(processorPixelColor(result, x: 4, y: 4) == [0, 255, 0])
}

@Test func resizeModeChangesCacheIdentity() throws {
    let asset = DataImageAsset(data: TestImageData.png, uniqueKey: "resize-mode-cache")
    let fitRequest = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: CGSize(width: 8, height: 8),
        resizeMode: .fit
    )
    let fillRequest = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: CGSize(width: 8, height: 8),
        resizeMode: .fill
    )

    #expect(fitRequest.cacheIdentifier != fillRequest.cacheIdentifier)
}

@Test func resizeProcessorReturnsSourceForZeroSizedRequest() async throws {
    let source = try await TestImageData.image()
    let asset = DataImageAsset(data: TestImageData.png, uniqueKey: "fixture")
    let request = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: .zero
    )

    let result = try await ResizeImageProcessor().process(source, for: request)

    #expect(result === source)
}

@Test func resizeProcessorAppliesTemplateRenderingMode() async throws {
    let source = try await TestImageData.image()
    let asset = DataImageAsset(data: TestImageData.png, uniqueKey: "template")
    let request = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: .zero,
        renderingMode: .template
    )

    let result = try await ResizeImageProcessor().process(source, for: request)

    #expect(result.isTemplateImage)
}

private actor ProcessorCallRecorder {
    private(set) var calls: [String] = []

    func record(_ name: String) {
        calls.append(name)
    }
}

private struct NamedImageProcessor: ImageProcessor {
    let name: String
    let recorder: ProcessorCallRecorder

    func process<Request: ImageRequest>(
        _ image: MediaImage,
        for request: Request
    ) async throws -> MediaImage {
        await recorder.record(name)
        return image
    }
}

private func processorFixtureImage() throws -> MediaImage {
    // A 6 × 2 image with a green center band and differently colored sides.
    let row: [[UInt8]] = [
        [255, 0, 0, 255], [255, 0, 0, 255],
        [0, 255, 0, 255], [0, 255, 0, 255],
        [0, 0, 255, 255], [0, 0, 255, 255],
    ]
    let data = Data((row + row).flatMap { $0 })
    let provider = try #require(CGDataProvider(data: data as CFData))
    let cgImage = try #require(CGImage(
        width: 6,
        height: 2,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: 24,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ))
    #if canImport(UIKit)
    return UIImage(cgImage: cgImage)
    #elseif canImport(AppKit)
    return NSImage(cgImage: cgImage, size: CGSize(width: 6, height: 2))
    #endif
}

private func processorPixelColor(_ image: MediaImage, x: Int, y: Int) -> [UInt8] {
    #if canImport(UIKit)
    let cgImage = image.cgImage!
    #elseif canImport(AppKit)
    var rect = CGRect(origin: .zero, size: image.size)
    let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    #endif

    var pixel = [UInt8](repeating: 0, count: 4)
    pixel.withUnsafeMutableBytes { bytes in
        guard let context = CGContext(
            data: bytes.baseAddress,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        context.draw(cgImage, in: CGRect(x: -x, y: -y, width: cgImage.width, height: cgImage.height))
    }
    return Array(pixel.prefix(3))
}
