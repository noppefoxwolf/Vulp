#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit
internal import Vulp_UIKit

/// A SwiftUI wrapper around Vulp's layer-backed UIKit image view.
///
/// The wrapped view sizes requests from its laid-out bounds by default and plays
/// animated image sequences using UIKit's display-synchronized playback.
public struct AsyncImage: View {
    /// Selects how the image request obtains its size.
    public enum SizingMode: String, Sendable {
        case explicitPixels
        case viewBounds
    }

    public var url: URL
    public var contentMode: ContentMode
    public var sizingMode: SizingMode
    public var levelOfIntegrity: Double
    public var prefetchCount: Int
    public var onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)?

    public init(
        url: URL,
        contentMode: ContentMode = .fit,
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

    public var body: some View {
        ImageViewRepresentable(
            url: url,
            contentMode: contentMode,
            sizingMode: sizingMode,
            levelOfIntegrity: levelOfIntegrity,
            prefetchCount: prefetchCount,
            onCompletion: onCompletion
        )
    }
}

private struct ImageViewRepresentable: UIViewRepresentable {
    var url: URL
    var contentMode: ContentMode
    var sizingMode: AsyncImage.SizingMode
    var levelOfIntegrity: Double
    var prefetchCount: Int
    var onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> Vulp_UIKit.AsyncImageView {
        let view = AsyncImageView()
        update(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: Vulp_UIKit.AsyncImageView, context: Context) {
        update(view, coordinator: context.coordinator)
    }

    func sizeThatFits(
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
        coordinator.onCompletion = onCompletion
        view.contentMode = contentMode == .fit ? .scaleAspectFit : .scaleAspectFill
        switch sizingMode {
        case .viewBounds: view.sizingMode = .viewBounds
        case .explicitPixels: view.sizingMode = .explicitPixels
        }

        guard coordinator.url != url
                || coordinator.levelOfIntegrity != levelOfIntegrity
                || coordinator.prefetchCount != prefetchCount
        else {
            return
        }

        coordinator.url = url
        coordinator.levelOfIntegrity = levelOfIntegrity
        coordinator.prefetchCount = prefetchCount
        view.loadImage(
            url: url,
            levelOfIntegrity: levelOfIntegrity,
            prefetchCount: prefetchCount
        ) { [weak coordinator] result in
            coordinator?.onCompletion?(result)
        }
    }

    @MainActor
    final class Coordinator {
        fileprivate var url: URL?
        fileprivate var levelOfIntegrity: Double?
        fileprivate var prefetchCount: Int?
        fileprivate var onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)?
    }
}
#endif
