import Foundation
import Testing
import Vulp

@MainActor
@Test func `Image placeholder generates its image away from the UI actor`() async throws {
    let expected = try await TestImageData.image()
    let isMainThread: @Sendable () -> Bool = { Thread.isMainThread }
    let placeholder = ImagePlaceholder(id: "blurhash") {
        #expect(!isMainThread())
        return expected
    }
    #expect(placeholder.id == "blurhash")
    let image = try await placeholder.image()
    #expect(image === expected)
}

private enum PlaceholderFailure: Error, Equatable { case unavailable }

@Test func `Image placeholder preserves generator errors`() async {
    let placeholder = ImagePlaceholder(id: "failure") { throw PlaceholderFailure.unavailable }
    await #expect(throws: PlaceholderFailure.unavailable) { try await placeholder.image() }
}

@Test func `Image placeholder can produce no image`() async throws {
    let placeholder = ImagePlaceholder(id: "empty") { nil }
    #expect(try await placeholder.image() == nil)
}
