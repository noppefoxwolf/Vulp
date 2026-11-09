import Foundation
import CoreGraphics

public struct ResizeImageProcessor: ImageProcessor {
    public init() {}

    @concurrent
    public func process<Request: MediaImageRequestProtocol>(
        _ image: MediaImage,
        for request: Request
    ) async throws -> MediaImage {
        let width = Int(request.targetSize.width.rounded())
        let height = Int(request.targetSize.height.rounded())
        guard width > 0, height > 0 else { return image }
        let source = image

        // Downsample into the requested bounds without changing the source aspect ratio.
        let scale = min(
            1,
            min(
                CGFloat(width) / CGFloat(source.width),
                CGFloat(height) / CGFloat(source.height)
            )
        )
        let outputWidth = min(width, max(1, Int((CGFloat(source.width) * scale).rounded())))
        let outputHeight = min(height, max(1, Int((CGFloat(source.height) * scale).rounded())))

        // Bitmap output requires an RGB space compatible with premultiplied alpha.
        let colorSpace = source.colorSpace?.model == .rgb
            ? source.colorSpace! : CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        let scaledWidth = CGFloat(source.width) * scale
        let scaledHeight = CGFloat(source.height) * scale
        let drawRect = CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)
        context.draw(source, in: drawRect)
        guard let resized = context.makeImage() else { return image }

        return resized
    }
}
