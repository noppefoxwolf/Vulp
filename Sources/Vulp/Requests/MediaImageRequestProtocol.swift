import Foundation

public enum ImageRenderingMode: String, Sendable {
    case original
    case template
}

public protocol MediaImageRequestProtocol: Sendable {
    var assetHandle: any MediaAsset { get }
    var targetSize: CGSize { get }
    var cacheIdentifier: String { get }
    var renderingMode: ImageRenderingMode { get }
    var decodingOptions: ImageDecodingOptions { get }
}

public typealias ImageRequest = MediaImageRequestProtocol

public extension MediaImageRequestProtocol {
    var renderingMode: ImageRenderingMode { .original }
    var decodingOptions: ImageDecodingOptions { .firstFrame }
}
