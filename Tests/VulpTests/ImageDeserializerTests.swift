import Foundation
import Vulp
import Testing

@Test func imageDeserializerDecodesPNGData() async throws {
    let image = try await ImageIOImageDeserializer().deserialize(TestImageData.png)

    #expect(image.pixelWidth == 1)
    #expect(image.pixelHeight == 1)
}

@Test func imageDeserializerRejectsInvalidData() async {
    do {
        _ = try await ImageIOImageDeserializer().deserialize(Data("not an image".utf8))
        Issue.record("Expected invalid image data to be rejected")
    } catch let error as ImageDeserializationError {
        #expect(error == .invalidData)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
