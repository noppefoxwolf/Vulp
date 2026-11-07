import Foundation
import MediaLoader
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

@Test func resizeProcessorProducesBucketedPixelSize() async throws {
    let source = try await TestImageData.image()
    let asset = DataImageAsset(data: TestImageData.png, uniqueKey: "fixture")
    let request = try ImageLoadRequest(
        assetHandle: asset,
        targetSize: CGSize(width: 12, height: 8)
    )

    let result = try await ResizeImageProcessor().process(source, for: request)

    #expect(result.pixelWidth == 16)
    #expect(result.pixelHeight == 11)
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
