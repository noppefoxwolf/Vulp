import CoreImage
import CoreImage.CIFilterBuiltins
import VulpUI

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
        let filter = CIFilter.sepiaTone()
        filter.inputImage = CIImage(cgImage: image)
        filter.intensity = Float(intensity)
        guard let output = filter.outputImage else { return image }

        let context = CIContext()
        guard let processed = context.createCGImage(output, from: output.extent) else {
            return image
        }

        return processed
    }
}
