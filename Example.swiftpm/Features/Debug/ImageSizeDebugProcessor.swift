import CoreGraphics
import CoreText
import Foundation
import VulpUI

struct ImageSizeDebugProcessor: ImageProcessor {
    let isEnabled: Bool

    @concurrent
    func process<Request: MediaImageRequestProtocol>(
        _ image: MediaImage,
        for request: Request
    ) async throws -> MediaImage {
        guard isEnabled else { return image }
        guard let context = makeContext(for: image) else { return image }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: bounds)
        drawSizeLabel(for: image, in: context, bounds: bounds)
        return context.makeImage() ?? image
    }

    private func makeContext(for image: CGImage) -> CGContext? {
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private func drawSizeLabel(for image: CGImage, in context: CGContext, bounds: CGRect) {
        let fontSize = min(18, max(10, CGFloat(image.width) / 18))
        let font = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)
        let text = "\(image.width) × \(image.height) px"
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let textHeight = ascent + descent + leading
        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 5
        let labelRect = CGRect(
            x: bounds.midX - (textWidth + horizontalPadding * 2) / 2,
            y: bounds.midY - (textHeight + verticalPadding * 2) / 2,
            width: textWidth + horizontalPadding * 2,
            height: textHeight + verticalPadding * 2
        )

        context.setFillColor(CGColor(gray: 0, alpha: 0.72))
        context.addPath(CGPath(
            roundedRect: labelRect,
            cornerWidth: verticalPadding,
            cornerHeight: verticalPadding,
            transform: nil
        ))
        context.fillPath()
        context.textPosition = CGPoint(
            x: labelRect.minX + horizontalPadding,
            y: labelRect.midY - (ascent - descent) / 2
        )
        CTLineDraw(line, context)
    }
}
