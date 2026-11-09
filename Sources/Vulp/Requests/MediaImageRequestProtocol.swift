import Foundation

/// Selects how a decoded bitmap is presented by a UI integration.
public enum ImageRenderingMode: String, Sendable {
    case original
    case template
}

public protocol MediaImageRequestProtocol: Sendable {
    var assetHandle: any MediaAsset { get }
    var targetSize: CGSize { get }
    var cacheIdentifier: String { get }
    /// Presentation metadata consumed by UI integrations; it does not alter decoded CGImage pixels.
    var renderingMode: ImageRenderingMode { get }
    var decodingOptions: ImageDecodingOptions { get }
}

public typealias ImageRequest = MediaImageRequestProtocol

public extension MediaImageRequestProtocol {
    var renderingMode: ImageRenderingMode { .original }
    var decodingOptions: ImageDecodingOptions { .firstFrame }
}
