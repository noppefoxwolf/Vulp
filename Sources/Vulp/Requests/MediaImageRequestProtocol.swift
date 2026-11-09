import Foundation

public protocol MediaImageRequestProtocol: Sendable {
    var assetHandle: any MediaAsset { get }
    var targetSize: CGSize { get }
    var cacheIdentifier: String { get }
    var decodingOptions: ImageDecodingOptions { get }
}

public typealias ImageRequest = MediaImageRequestProtocol

public extension MediaImageRequestProtocol {
    var decodingOptions: ImageDecodingOptions { .firstFrame }
}
