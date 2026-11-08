import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct ResizeImageProcessor: ImageProcessor {
    public init() {}

    @concurrent
    public func process<Request: MediaImageRequestProtocol>(
        _ image: MediaImage,
        for request: Request
    ) async throws -> MediaImage {
        let width = Int(request.targetSize.width.rounded())
        let height = Int(request.targetSize.height.rounded())
        let renderingMode = request.renderingMode
        guard width > 0, height > 0 else {
            return applying(renderingMode, to: image)
        }
        guard let source = image.cgImageRepresentation else {
            return applying(renderingMode, to: image)
        }

        let scale = min(
            CGFloat(width) / CGFloat(source.width),
            CGFloat(height) / CGFloat(source.height)
        )
        let outputWidth = max(1, Int((CGFloat(source.width) * scale).rounded()))
        let outputHeight = max(1, Int((CGFloat(source.height) * scale).rounded()))

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
        context.draw(source, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        guard let resized = context.makeImage() else { return image }

        #if canImport(UIKit)
        return applying(renderingMode, to: UIImage(cgImage: resized, scale: 1, orientation: .up))
        #elseif canImport(AppKit)
        return applying(renderingMode, to: NSImage(
            cgImage: resized,
            size: CGSize(width: outputWidth, height: outputHeight)
        ))
        #else
        return image
        #endif
    }

    private func applying(_ mode: ImageRenderingMode, to image: MediaImage) -> MediaImage {
        #if canImport(UIKit)
        return image.withRenderingMode(mode == .template ? .alwaysTemplate : .alwaysOriginal)
        #elseif canImport(AppKit)
        image.isTemplate = mode == .template
        return image
        #else
        image
        #endif
    }
}

private extension MediaImage {
    var cgImageRepresentation: CGImage? {
        #if canImport(UIKit)
        cgImage
        #elseif canImport(AppKit)
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        nil
        #endif
    }
}
