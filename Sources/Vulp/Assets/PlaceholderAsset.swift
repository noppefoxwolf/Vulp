import Foundation
import CoreGraphics

/// A placeholder's stable identity and asynchronous image generator.
/// Change the ID when the generated content changes.
public struct PlaceholderAsset: Identifiable, Sendable {
    public let id: String
    private let generateImage: @Sendable () async throws -> CGImage?

    public init(
        id: String,
        _ generateImage: @escaping @Sendable () async throws -> CGImage?
    ) {
        self.id = id
        self.generateImage = generateImage
    }

    /// Generates the image away from the caller's actor. Reuse is managed by the image view.
    @concurrent
    public func image() async throws -> CGImage? {
        try await generateImage()
    }
}
