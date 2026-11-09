import CoreGraphics
import Foundation
import ImageIO
import Vulp
import Testing

@Test(arguments: [Optional<Int>.none, 16])
func decoderAppliesEXIFOrientation(maximumPixelDimension: Int?) async throws {
    let context = try #require(CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))

    let result = try await ImageIOImageDecoder().deserialize(data as Data, options: .firstFrame,
        maximumPixelDimension: maximumPixelDimension)
    #expect(result.pixelHeight == result.pixelWidth * 2)
}

@Test(arguments: [false, true])
func resizeConvertsNonRGBImages(cmyk: Bool) async throws {
    let colorSpace = cmyk ? CGColorSpaceCreateDeviceCMYK() : CGColorSpaceCreateDeviceGray()
    let components = cmyk ? 4 : 1
    let provider = try #require(CGDataProvider(data: Data(repeating: 128, count: 8 * 4 * components) as CFData))
    let source = try #require(CGImage(width: 8, height: 4, bitsPerComponent: 8,
        bitsPerPixel: 8 * components, bytesPerRow: 8 * components, space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.tiff" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, source, nil)
    #expect(CGImageDestinationFinalize(destination))
    let image = try await ImageIOImageDecoder().deserialize(data as Data)
    let request = try MediaImageRequest(assetHandle: DataMediaAsset(data: data as Data),
        targetSize: CGSize(width: 16, height: 16), renderingMode: .template)
    let result = try await ResizeImageProcessor().process(image, for: request)
    #expect(result.pixelWidth == 16)
    #expect(result.pixelHeight == 16)
    #expect(result.isTemplateImage)
}
