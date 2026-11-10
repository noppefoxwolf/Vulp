#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit
@_exported import Vulp_UIKit

/// A SwiftUI wrapper around Vulp's layer-backed UIKit image view.
///
/// The wrapped view sizes requests from its laid-out bounds by default and plays
/// animated image sequences using UIKit's display-synchronized playback.
public struct UIKitAsyncImage: UIViewRepresentable {
    public var url: URL
    public var contentMode: UIView.ContentMode
    public var sizingMode: ImageViewSizingMode
    public var levelOfIntegrity: Double
    public var prefetchCount: Int
    public var onFailure: (@MainActor @Sendable (any Error) -> Void)?

    public init(
        url: URL,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        sizingMode: ImageViewSizingMode = .viewBounds,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        onFailure: (@MainActor @Sendable (any Error) -> Void)? = nil
    ) {
        self.url = url
        self.contentMode = contentMode
        self.sizingMode = sizingMode
        self.levelOfIntegrity = levelOfIntegrity
        self.prefetchCount = prefetchCount
        self.onFailure = onFailure
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> AsyncImageView {
        let view = AsyncImageView()
        update(view, coordinator: context.coordinator)
        return view
    }

    public func updateUIView(_ view: AsyncImageView, context: Context) {
        update(view, coordinator: context.coordinator)
    }

    private func update(_ view: AsyncImageView, coordinator: Coordinator) {
        coordinator.onFailure = onFailure
        view.contentMode = contentMode
        view.sizingMode = sizingMode

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
        ) { [weak coordinator] error in
            coordinator?.onFailure?(error)
        }
    }

    @MainActor
    public final class Coordinator {
        fileprivate var url: URL?
        fileprivate var levelOfIntegrity: Double?
        fileprivate var prefetchCount: Int?
        fileprivate var onFailure: (@MainActor @Sendable (any Error) -> Void)?
    }
}
#endif
