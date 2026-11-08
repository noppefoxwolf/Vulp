import Foundation

public enum MediaImageRequestError: Error, Equatable {
    case invalidTargetSize
}

public typealias ImageLoadRequestError = MediaImageRequestError

/// The first concrete request type used by the standard image-loading pipeline.
public struct MediaImageRequest: MediaImageRequestProtocol {
    public let assetHandle: any MediaAsset
    public let targetSize: CGSize
    public let renderingMode: ImageRenderingMode
    public let resizeMode: ImageResizeMode
    public let decodingOptions: ImageDecodingOptions
    public let cacheIdentifier: String

    static func makeCacheIdentifier(
        asset: any MediaAsset,
        targetSize: CGSize,
        renderingMode: ImageRenderingMode,
        resizeMode: ImageResizeMode = .fit,
        decodingOptions: ImageDecodingOptions = .firstFrame
    ) -> String {
        let decodingKey: String
        switch decodingOptions {
        case .firstFrame:
            decodingKey = ""
        case .frame(let index):
            decodingKey = "|frame:\(index)"
        }
        return "\(asset.uniqueKey)|\(targetSize.width)x\(targetSize.height)|\(renderingMode.rawValue)|resize:\(resizeMode.rawValue)\(decodingKey)"
    }

    /// Creates a request from a point size and display scale. Use the default scale of `1` for explicit pixel dimensions.
    /// - Parameter resizeMode: Fits the whole source or fills and center-crops the requested size.
    public init(
        assetHandle: any MediaAsset,
        targetSize: CGSize,
        scale: CGFloat = 1,
        renderingMode: ImageRenderingMode = .original,
        resizeMode: ImageResizeMode = .fit,
        decodingOptions: ImageDecodingOptions = .firstFrame,
        cacheIdentifier: String? = nil
    ) throws {
        guard targetSize.width.isFinite,
              targetSize.height.isFinite,
              targetSize.width >= 0,
              targetSize.height >= 0,
              scale.isFinite,
              scale > 0
        else {
            throw MediaImageRequestError.invalidTargetSize
        }

        let pixelSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        guard pixelSize.width.isFinite,
              pixelSize.height.isFinite,
              let bucketedPixelSize = ImageSizeBucket.pixelSize(for: pixelSize)
        else {
            throw MediaImageRequestError.invalidTargetSize
        }

        self.assetHandle = assetHandle
        self.targetSize = bucketedPixelSize
        self.renderingMode = renderingMode
        self.resizeMode = resizeMode
        self.decodingOptions = decodingOptions
        if let cacheIdentifier {
            self.cacheIdentifier = cacheIdentifier
        } else {
            self.cacheIdentifier = Self.makeCacheIdentifier(
                asset: assetHandle,
                targetSize: bucketedPixelSize,
                renderingMode: renderingMode,
                resizeMode: resizeMode,
                decodingOptions: decodingOptions
            )
        }
    }
}

public typealias ImageLoadRequest = MediaImageRequest
