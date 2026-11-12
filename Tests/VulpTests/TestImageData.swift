import Foundation
import Vulp
import Testing

enum TestImageData {
    // A valid one-pixel PNG fixture.
    static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZ1sAAAAASUVORK5CYII="
    )!

    static func fileURL(for data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VulpTests-\(UUID().uuidString)", isDirectory: false)
        try data.write(to: url)
        return url
    }

    static func image() async throws -> MediaImage {
        let url = try fileURL(for: png)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await ImageIOImageDecoder().decode(
            from: url,
            options: .firstFrame,
            maximumPixelDimension: nil
        )
    }
}
