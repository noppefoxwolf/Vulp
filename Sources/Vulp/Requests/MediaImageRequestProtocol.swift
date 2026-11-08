import Foundation

public enum ImageRenderingMode: String, Sendable {
    case original
    case template
}

/// Controls how the source image is resized into the requested bounding size.
public enum ImageResizeMode: String, Hashable, Sendable {
    /// Keeps the whole image visible and fits it inside the requested size.
    case fit
    /// Covers the requested size and center-crops any overflow.
    case fill
}

public protocol MediaImageRequestProtocol: Sendable {
    var assetHandle: any MediaAsset { get }
    var targetSize: CGSize { get }
    var cacheIdentifier: String { get }
    var renderingMode: ImageRenderingMode { get }
    var resizeMode: ImageResizeMode { get }
    var decodingOptions: ImageDecodingOptions { get }
}

public typealias ImageRequest = MediaImageRequestProtocol

public extension MediaImageRequestProtocol {
    var renderingMode: ImageRenderingMode { .original }
    var resizeMode: ImageResizeMode { .fit }
    var decodingOptions: ImageDecodingOptions { .firstFrame }
}
