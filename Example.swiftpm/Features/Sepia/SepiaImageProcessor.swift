import CoreImage
import CoreImage.CIFilterBuiltins
import MediaLoaderUI
import UIKit

struct SepiaImageProcessor: ImageProcessor {
    let intensity: Double

    init(intensity: Double) {
        self.intensity = min(max(intensity, 0), 1)
    }

    @concurrent
    func process<Request: MediaImageRequestProtocol>(
        _ image: MediaImage,
        for request: Request
    ) async throws -> MediaImage {
        guard let source = image.cgImage else { return image }

        let filter = CIFilter.sepiaTone()
        filter.inputImage = CIImage(cgImage: source)
        filter.intensity = Float(intensity)
        guard let output = filter.outputImage else { return image }

        let context = CIContext()
        guard let processed = context.createCGImage(output, from: output.extent) else {
            return image
        }

        return UIImage(
            cgImage: processed,
            scale: image.scale,
            orientation: image.imageOrientation
        ).withRenderingMode(image.renderingMode)
    }
}
