import Foundation
import Testing
import Vulp

@MainActor
@Test func `Placeholder asset generates its image away from the UI actor`() async throws {
    let expected = try await TestImageData.image()
    let isMainThread: @Sendable () -> Bool = { Thread.isMainThread }
    let asset = PlaceholderAsset(id: "blurhash") {
        #expect(!isMainThread())
        return expected
    }
    #expect(asset.id == "blurhash")
    let image = try await asset.image()
    #expect(image === expected)
}

private enum PlaceholderFailure: Error, Equatable { case unavailable }

@Test func `Placeholder asset preserves generator errors`() async {
    let asset = PlaceholderAsset(id: "failure") { throw PlaceholderFailure.unavailable }
    await #expect(throws: PlaceholderFailure.unavailable) { try await asset.image() }
}

@Test func `Placeholder asset can produce no image`() async throws {
    let asset = PlaceholderAsset(id: "empty") { nil }
    #expect(try await asset.image() == nil)
}
