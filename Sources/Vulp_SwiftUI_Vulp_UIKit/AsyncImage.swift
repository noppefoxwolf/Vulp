#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit
import Vulp_UIKit

/// A SwiftUI wrapper around Vulp's layer-backed UIKit image view.
///
/// The public configuration uses SwiftUI and Vulp types. The concrete Vulp
/// UIKit view stays inside the implementation; `UIView` is used for the
/// `UIViewRepresentable` protocol witnesses.
public struct AsyncImage: UIViewRepresentable {
    public enum SizingMode: Sendable {
        case explicitPixels
        case viewBounds
    }

    public var url: URL
    public var contentMode: SwiftUI.ContentMode
    public var sizingMode: SizingMode
    public var levelOfIntegrity: Double
    public var prefetchCount: Int
    public var onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)?

    public init(
        url: URL,
        contentMode: SwiftUI.ContentMode = .fit,
        sizingMode: SizingMode = .viewBounds,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)? = nil
    ) {
        self.url = url
        self.contentMode = contentMode
        self.sizingMode = sizingMode
        self.levelOfIntegrity = levelOfIntegrity
        self.prefetchCount = prefetchCount
        self.onCompletion = onCompletion
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> UIView {
        let view = Vulp_UIKit.AsyncImageView()
        context.coordinator.imageView = view
        update(view, coordinator: context.coordinator)
        return view
    }

    public func updateUIView(_: UIView, context: Context) {
        guard let imageView = context.coordinator.imageView else {
            return
        }
        update(imageView, coordinator: context.coordinator)
    }

    public func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIView,
        context _: Context
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

    private func update(
        _ imageView: Vulp_UIKit.AsyncImageView,
        coordinator: Coordinator
    ) {
        coordinator.onCompletion = onCompletion
        imageView.contentMode = contentMode.uiKitContentMode
        imageView.sizingMode = sizingMode.uiKitSizingMode

        guard coordinator.url != url
                || coordinator.levelOfIntegrity != levelOfIntegrity
                || coordinator.prefetchCount != prefetchCount
        else {
            return
        }

        coordinator.url = url
        coordinator.levelOfIntegrity = levelOfIntegrity
        coordinator.prefetchCount = prefetchCount
        imageView.loadImage(
            url: url,
            levelOfIntegrity: levelOfIntegrity,
            prefetchCount: prefetchCount
        ) { [weak coordinator] result in
            coordinator?.onCompletion?(result)
        }
    }

    @MainActor
    public final class Coordinator {
        fileprivate weak var imageView: Vulp_UIKit.AsyncImageView?
        fileprivate var url: URL?
        fileprivate var levelOfIntegrity: Double?
        fileprivate var prefetchCount: Int?
        fileprivate var onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)?
    }
}

private extension AsyncImage.SizingMode {
    var uiKitSizingMode: ImageViewSizingMode {
        switch self {
        case .explicitPixels: .explicitPixels
        case .viewBounds: .viewBounds
        }
    }
}

private extension SwiftUI.ContentMode {
    var uiKitContentMode: UIView.ContentMode {
        switch self {
        case .fit: .scaleAspectFit
        case .fill: .scaleAspectFill
        @unknown default: .scaleAspectFit
        }
    }
}
#endif
