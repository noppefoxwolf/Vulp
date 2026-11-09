import CoreGraphics
import Foundation
import Vulp
import Testing

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

@Test func resizeProcessorDoesNotUpscaleSmallSourceToBucketSize() async throws {
    let source = try await TestImageData.image()
    let asset = DataImageAsset(data: TestImageData.png, uniqueKey: "fixture")
    let request = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: CGSize(width: 12, height: 8)
    )

    let result = try await ResizeImageProcessor().process(source, for: request)

    #expect(result.pixelWidth == 1)
    #expect(result.pixelHeight == 1)
}

@Test func resizeProcessorDownsamplesWithoutChangingSourceAspectRatio() async throws {
    let source = try processorFixtureImage()
    let asset = DataImageAsset(data: TestImageData.png, uniqueKey: "fit-resize")
    let request = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: CGSize(width: 8, height: 8)
    )

    let result = try await ResizeImageProcessor().process(source, for: request)

    #expect(result.pixelWidth == 6)
    #expect(result.pixelHeight == 2)
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

@Test func resizeProcessorKeepsTemplateModeSeparateFromBitmap() async throws {
    let source = try await TestImageData.image()
    let asset = DataImageAsset(data: TestImageData.png, uniqueKey: "template")
    let request = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: .zero,
        renderingMode: .template
    )

    let result = try await ResizeImageProcessor().process(source, for: request)

    #expect(result === source)
    #expect(request.renderingMode == .template)
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
    return cgImage
}

private func processorPixelColor(_ image: MediaImage, x: Int, y: Int) -> [UInt8] {
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
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
    }
    return Array(pixel.prefix(3))
}
