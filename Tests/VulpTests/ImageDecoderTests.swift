import Foundation
import Vulp
import Testing

@Test func imageDecoderDecodesPNGFile() async throws {
    let url = try TestImageData.fileURL(for: TestImageData.png)
    defer { try? FileManager.default.removeItem(at: url) }
    let image = try await ImageIOImageDecoder().decode(
        from: url,
        options: .firstFrame,
        maximumPixelDimension: nil
    )

    #expect(image.width == 1)
    #expect(image.height == 1)
}

@Test func imageIODecoderRecognizesLocalImageFileURL() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("VulpTests-\(UUID().uuidString)", isDirectory: false)
    defer { try? FileManager.default.removeItem(at: url) }
    try TestImageData.png.write(to: url)

    let canDecode = await ImageIOImageDecoder().canDecode(url: url)
    #expect(canDecode)
}

@Test func imageDecoderRejectsInvalidFile() async throws {
    let url = try TestImageData.fileURL(for: Data("not an image".utf8))
    defer { try? FileManager.default.removeItem(at: url) }
    do {
        _ = try await ImageIOImageDecoder().decode(
            from: url,
            options: .firstFrame,
            maximumPixelDimension: nil
        )
        Issue.record("Expected invalid image data to be rejected")
    } catch let error as ImageDecodingError {
        #expect(error == .invalidData)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
