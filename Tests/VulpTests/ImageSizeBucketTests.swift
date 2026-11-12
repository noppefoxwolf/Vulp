import Foundation
import Vulp
import Testing

@Test func imageSizeBucketRoundsLongestDimensionUpToSquareRootOfTwoTierAndPreservesAspectRatio() {
    let size = ImageSizeBucket.pixelSize(for: CGSize(width: 300, height: 200))

    #expect(size == CGSize(width: 362, height: 241))
}

@Test func imageSizeBucketAddsOneTierBetweenPowersOfTwo() {
    #expect(ImageSizeBucket.pixelSize(for: CGSize(width: 512, height: 256)) == CGSize(width: 512, height: 256))
    #expect(ImageSizeBucket.pixelSize(for: CGSize(width: 700, height: 350)) == CGSize(width: 724, height: 362))
}

@Test func imageSizeBucketUsesSameTierForNearbySizes() throws {
    let asset = DataMediaAsset(data: TestImageData.png, uniqueKey: "bucket")
    let first = try MediaImageRequest(asset: asset, targetSize: CGSize(width: 300, height: 200))
    let second = try MediaImageRequest(asset: asset, targetSize: CGSize(width: 320, height: 213))

    #expect(first.targetSize == CGSize(width: 362, height: 241))
    #expect(second.targetSize == first.targetSize)
    #expect(second.cacheIdentifier == first.cacheIdentifier)
}

@Test func requestScaleConvertsPointSizeToBucketedPixels() throws {
    let request = try MediaImageRequest(
        asset: DataMediaAsset(data: TestImageData.png, uniqueKey: "scaled"),
        targetSize: CGSize(width: 100, height: 50),
        scale: 2
    )

    #expect(request.targetSize == CGSize(width: 256, height: 128))
}

@Test func requestRejectsInvalidScale() {
    #expect(throws: MediaImageRequestError.invalidTargetSize) {
        try MediaImageRequest(
            asset: DataMediaAsset(data: TestImageData.png, uniqueKey: "invalid-scale"),
            targetSize: CGSize(width: 100, height: 50),
            scale: 0
        )
    }
}

@Test func imageSizeBucketKeepsZeroAndRejectsNonFiniteDimensions() {
    #expect(ImageSizeBucket.pixelSize(for: .zero) == .zero)
    #expect(ImageSizeBucket.pixelSize(for: CGSize(width: CGFloat.infinity, height: 10)) == nil)
}
