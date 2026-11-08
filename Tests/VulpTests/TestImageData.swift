import Foundation
import Vulp
import Testing

enum TestImageData {
    // A valid one-pixel PNG fixture.
    static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
    )!

    static func image() async throws -> MediaImage {
        try await ImageIOImageDeserializer().deserialize(png)
    }
}
