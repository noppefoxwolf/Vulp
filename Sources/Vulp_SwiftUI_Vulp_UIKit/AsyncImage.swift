#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit
public import Vulp_UIKit

/// A SwiftUI wrapper around Vulp's layer-backed UIKit image view.
///
/// The wrapped view sizes requests from its laid-out bounds by default and plays
/// animated image sequences using UIKit's display-synchronized playback.
public struct AsyncImage: UIViewRepresentable {
    /// Selects how the image request obtains its size.
    public enum SizingMode: String, Sendable {
        case explicitPixels
        case viewBounds
    }

    public var asset: any MediaAsset
    public var contentMode: ContentMode
    public var sizingMode: SizingMode
    public var levelOfIntegrity: Double
    public var prefetchCount: Int
    /// Change the asset ID to replace the placeholder while keeping the same image source.
    public var placeholder: ImagePlaceholder?
    public var onStart: (@MainActor @Sendable () -> Void)?
    public var onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)?

    public init(
        url: URL,
        contentMode: ContentMode = .fit,
        sizingMode: SizingMode = .viewBounds,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        placeholder: ImagePlaceholder? = nil,
        onStart: (@MainActor @Sendable () -> Void)? = nil,
        onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)? = nil
    ) {
        let asset: any MediaAsset = url.isFileURL ? FileMediaAsset(url: url) : RemoteMediaAsset(url: url)
        self.init(
            asset: asset,
            contentMode: contentMode,
            sizingMode: sizingMode,
            levelOfIntegrity: levelOfIntegrity,
            prefetchCount: prefetchCount,
            placeholder: placeholder,
            onStart: onStart,
            onCompletion: onCompletion
        )
    }

    public init(
        asset: any MediaAsset,
        contentMode: ContentMode = .fit,
        sizingMode: SizingMode = .viewBounds,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        placeholder: ImagePlaceholder? = nil,
        onStart: (@MainActor @Sendable () -> Void)? = nil,
        onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)? = nil
    ) {
        self.asset = asset
        self.contentMode = contentMode
        self.sizingMode = sizingMode
        self.levelOfIntegrity = levelOfIntegrity
        self.prefetchCount = prefetchCount
        self.placeholder = placeholder
        self.onStart = onStart
        self.onCompletion = onCompletion
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> Vulp_UIKit.AsyncImageView {
        let view = AsyncImageView()
        update(view, coordinator: context.coordinator)
        return view
    }

    public func updateUIView(_ view: Vulp_UIKit.AsyncImageView, context: Context) {
        update(view, coordinator: context.coordinator)
    }

    public func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: Vulp_UIKit.AsyncImageView,
        context: Context
    ) -> CGSize? {
        switch sizingMode {
        case .viewBounds:
            guard let width = proposal.width, width.isFinite,
                  let height = proposal.height, height.isFinite
            else {
                return nil
            }
            return CGSize(width: width, height: height)
        case .explicitPixels:
            let intrinsicSize = uiView.intrinsicContentSize
            guard intrinsicSize.width != UIView.noIntrinsicMetric,
                  intrinsicSize.height != UIView.noIntrinsicMetric,
                  intrinsicSize.width > 0,
                  intrinsicSize.height > 0
            else {
                return nil
            }

            let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
            let height = proposal.height.flatMap { $0.isFinite ? $0 : nil }
            switch (width, height) {
            case let (width?, height?):
                return CGSize(width: width, height: height)
            case let (width?, nil):
                return CGSize(
                    width: width,
                    height: width * intrinsicSize.height / intrinsicSize.width
                )
            case let (nil, height?):
                return CGSize(
                    width: height * intrinsicSize.width / intrinsicSize.height,
                    height: height
                )
            case (nil, nil):
                return intrinsicSize
            }
        }
    }

    private func update(_ view: Vulp_UIKit.AsyncImageView, coordinator: Coordinator) {
        coordinator.onStart = onStart
        coordinator.onCompletion = onCompletion
        view.delegate = coordinator
        view.contentMode = UIView.ContentMode(contentMode)
        view.sizingMode = ImageViewSizingMode(sizingMode)

        let assetKey = asset.uniqueKey
        guard coordinator.assetKey != assetKey
                || coordinator.levelOfIntegrity != levelOfIntegrity
                || coordinator.prefetchCount != prefetchCount
        else {
            view.setPlaceholder(placeholder)
            return
        }

        coordinator.assetKey = assetKey
        coordinator.levelOfIntegrity = levelOfIntegrity
        coordinator.prefetchCount = prefetchCount
        view.loadImage(
            asset: asset,
            levelOfIntegrity: levelOfIntegrity,
            prefetchCount: prefetchCount
        )
        view.setPlaceholder(placeholder)
    }

    @MainActor
    public final class Coordinator: AsyncImageViewDelegate {
        public func asyncImageViewDidStartLoading(_ imageView: AsyncImageView) {
            onStart?()
        }

        public func asyncImageView(
            _ imageView: AsyncImageView,
            didComplete result: Result<CGImage, any Error>
        ) {
            onCompletion?(result)
        }

        fileprivate var assetKey: String?
        fileprivate var levelOfIntegrity: Double?
        fileprivate var prefetchCount: Int?
        fileprivate var onStart: (@MainActor @Sendable () -> Void)?
        fileprivate var onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)?
    }
}
private extension UIView.ContentMode {
    init(_ contentMode: SwiftUI.ContentMode) {
        switch contentMode {
        case .fit: self = .scaleAspectFit
        case .fill: self = .scaleAspectFill
        }
    }
}

private extension ImageViewSizingMode {
    init(_ sizingMode: AsyncImage.SizingMode) {
        switch sizingMode {
        case .viewBounds: self = .viewBounds
        case .explicitPixels: self = .explicitPixels
        }
    }
}
#endif
