import CoreGraphics
import Foundation
@testable import Vulp
import Testing

@Test func imageSequencePlaybackPlanSelectsRefreshRateFromFrameTiming() {
    let plan = ImageSequencePlaybackPlan(
        frameDurations: Array(repeating: 1.0 / 30.0, count: 30),
        levelOfIntegrity: 1
    )

    #expect(ImageSequenceFrameRate.allCases.map(\.rawValue) == [60, 30, 20, 15, 12, 10, 6, 5, 4, 3, 2, 1])
    #expect(plan.frameRate == .fps30)
    #expect(plan.frameIndices.count >= 30)
}

@Test func imageSequencePlaybackPlanClampsIntegrityAndDropsFrames() {
    let fullIntegrityPlan = ImageSequencePlaybackPlan(
        frameDurations: Array(repeating: 1.0 / 30.0, count: 30),
        levelOfIntegrity: 1
    )
    let lowIntegrityPlan = ImageSequencePlaybackPlan(
        frameDurations: Array(repeating: 1.0 / 30.0, count: 30),
        levelOfIntegrity: 0
    )
    let negativeIntegrityPlan = ImageSequencePlaybackPlan(
        frameDurations: Array(repeating: 1.0 / 30.0, count: 30),
        levelOfIntegrity: -0.5
    )
    let excessiveIntegrityPlan = ImageSequencePlaybackPlan(
        frameDurations: Array(repeating: 1.0 / 30.0, count: 30),
        levelOfIntegrity: 1.5
    )

    #expect(lowIntegrityPlan.frameIndices.count < fullIntegrityPlan.frameIndices.count)
    #expect(negativeIntegrityPlan.frameIndices == lowIntegrityPlan.frameIndices)
    #expect(excessiveIntegrityPlan.frameIndices == fullIntegrityPlan.frameIndices)
}

private enum AnimatedGIFFixture {
    static let data = Data(base64Encoded:
        "R0lGODlhEAAQAPf/MQAA//4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAP4AAAD/ACH/C05FVFNDQVBFMi4wAwEAAAAh+QQEZAAfACwAAAAAEAAQAAAIHQADCBxIsKDBgwgTKlzIsKHDhxAjSpxIsaLFgQEBACH5BAVkAP8ALAAAAAAQABAAAAgdAAEIHEiwoMGDCBMqXMiwocOHECNKnEixosWBAQEAOw=="
    )!
}

private actor RecordingSequenceDownloader: ImageDataDownloader {
    private(set) var requestCount = 0
    let data: Data

    init(data: Data) {
        self.data = data
    }

    func download(from url: URL) async throws -> Data {
        requestCount += 1
        return data
    }
}

@Test func imageIODecoderReportsAndSelectsSequenceFrames() async throws {
    let deserializer = ImageIOImageDeserializer()

    #expect(try await deserializer.frameCount(in: AnimatedGIFFixture.data) == 2)
    let frameDurations = try await deserializer.frameDurations(in: AnimatedGIFFixture.data)
    #expect(frameDurations.count == 2)
    #expect(frameDurations.allSatisfy { $0 > 0 })

    let firstFrame = try await deserializer.deserialize(
        AnimatedGIFFixture.data,
        options: .frame(index: 0)
    )
    let secondFrame = try await deserializer.deserialize(
        AnimatedGIFFixture.data,
        options: .frame(index: 1)
    )

    #expect(firstFrame.width == 16)
    #expect(secondFrame.width == 16)
    #expect(pixelColor(firstFrame) != pixelColor(secondFrame))
}

@Test(arguments: ["two-frame.apng", "two-frame.webp"])
func imageIODecoderReportsAndSelectsAPNGAndWebPFrames(filename: String) async throws {
    let url = try #require(Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    let deserializer = ImageIOImageDeserializer()

    #expect(try await deserializer.frameCount(in: data) == 2)
    let frameDurations = try await deserializer.frameDurations(in: data)
    #expect(frameDurations.count == 2)
    #expect(frameDurations.allSatisfy { $0 > 0 })

    let firstFrame = try await deserializer.deserialize(data, options: .frame(index: 0))
    let secondFrame = try await deserializer.deserialize(data, options: .frame(index: 1))

    #expect(firstFrame.width == 16)
    #expect(secondFrame.width == 16)
    #expect(pixelColor(firstFrame) != pixelColor(secondFrame))
}

@Test func imageSequenceRejectsAnOutOfBoundsFrameIndex() async throws {
    let sequence = try await ImageIOImageDeserializer().loadSequence(
        AnimatedGIFFixture.data,
        identifier: "fixture"
    )

    #expect(throws: ImageSequenceError.invalidFrameIndex(2)) {
        try sequence.frameRequest(at: 2, targetSize: CGSize(width: 16, height: 16))
    }
}

@Test func imageSequenceFrameLoaderLoadsFramesOnDemand() async throws {
    let downloader = RecordingSequenceDownloader(data: AnimatedGIFFixture.data)
    let cache = InMemoryImageCache()
    let loader = DefaultImageLoader(
        downloader: downloader,
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: cache
    )
    let asset = RemoteImageAsset(
        url: URL(string: "https://example.com/animated.gif")!,
        uniqueKey: "animated-fixture-\(UUID().uuidString)"
    )
    let sequence = try await loader.loadSequence(from: asset)
    let frameLoader = ImageSequenceFrameLoader(
        sequence: sequence,
        using: loader,
        targetSize: CGSize(width: 16, height: 16),
        prefetchCount: 0
    )

    let first = try await frameLoader.frame(at: 0)
    let secondRequest = try sequence.frameRequest(
        at: 1,
        targetSize: CGSize(width: 16, height: 16)
    )

    #expect(await cache.image(forKey: secondRequest.cacheIdentifier) == nil)
    let second = try await frameLoader.frame(at: 1)

    #expect(pixelColor(first) != pixelColor(second))
    #expect(await cache.image(forKey: secondRequest.cacheIdentifier) != nil)
    #expect(await downloader.requestCount == 1)
}

@Test func imageSequenceFrameLoaderPrefetchesFollowingPlaybackFrames() async throws {
    let downloader = RecordingSequenceDownloader(data: AnimatedGIFFixture.data)
    let loader = DefaultImageLoader(
        downloader: downloader,
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let sequence = ImageSequence(
        identifier: "sampled-sequence",
        data: AnimatedGIFFixture.data,
        frameDurations: Array(repeating: 0.1, count: 7)
    )
    let frameLoader = ImageSequenceFrameLoader(
        sequence: sequence,
        using: loader,
        targetSize: CGSize(width: 16, height: 16),
        prefetchCount: 3,
        playbackFrameIndices: [0, 2, 4, 6]
    )

    #expect(await frameLoader.frameWindow(startingAt: 0) == [0, 2, 4, 6])
    #expect(await frameLoader.frameWindow(startingAt: 4) == [4, 6, 0, 2])
}

@Test func imageSequenceLoaderFetchesSourceOnceAndCachesEachFrame() async throws {
    let downloader = RecordingSequenceDownloader(data: AnimatedGIFFixture.data)
    let loader = DefaultImageLoader(
        downloader: downloader,
        deserializer: ImageIOImageDeserializer(),
        processor: ResizeImageProcessor(),
        cache: InMemoryImageCache()
    )
    let asset = RemoteImageAsset(
        url: URL(string: "https://example.com/animated.gif")!,
        uniqueKey: "animated-fixture-\(UUID().uuidString)"
    )
    let sequence = try await loader.loadSequence(from: asset)
    let firstRequest = try sequence.frameRequest(
        at: 0,
        targetSize: CGSize(width: 16, height: 16)
    )
    let secondRequest = try sequence.frameRequest(
        at: 1,
        targetSize: CGSize(width: 16, height: 16)
    )

    let frames = try await sequence.loadFrames(
        using: loader,
        targetSize: CGSize(width: 16, height: 16)
    )
    let cachedFirstFrame = try await loader.load(firstRequest)

    #expect(firstRequest.cacheIdentifier != secondRequest.cacheIdentifier)
    #expect(frames.count == 2)
    #expect(frames[0] === cachedFirstFrame)
    #expect(pixelColor(frames[0]) != pixelColor(frames[1]))
    #expect(await downloader.requestCount == 1)
}

private func pixelColor(_ image: MediaImage) -> [UInt8] {
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
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return Array(pixel.prefix(3))
}
