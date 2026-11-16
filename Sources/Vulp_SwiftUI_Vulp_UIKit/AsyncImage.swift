#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit
@_exported import Vulp_UIKit

/// A SwiftUI wrapper around Vulp's layer-backed UIKit image view.
///
/// The wrapped view sizes requests from its laid-out bounds by default and plays
/// animated image sequences using UIKit's display-synchronized playback.
public struct AsyncImage: UIViewRepresentable {
    public var url: URL
    public var contentMode: UIView.ContentMode
    public var sizingMode: ImageViewSizingMode
    public var levelOfIntegrity: Double
    public var prefetchCount: Int
    public var onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)?
    public var onSetup: (@MainActor (Vulp_UIKit.AsyncImageView) -> Void)?
    public var placeholder: (@MainActor @Sendable () async throws -> CGImage)?

    public init(
        url: URL,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        sizingMode: ImageViewSizingMode = .viewBounds,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)? = nil,
        onSetup: (@MainActor (Vulp_UIKit.AsyncImageView) -> Void)? = nil,
        placeholder: (@MainActor @Sendable () async throws -> CGImage)? = nil
    ) {
        self.url = url
        self.contentMode = contentMode
        self.sizingMode = sizingMode
        self.levelOfIntegrity = levelOfIntegrity
        self.prefetchCount = prefetchCount
        self.onCompletion = onCompletion
        self.onSetup = onSetup
        self.placeholder = placeholder
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
        coordinator.onCompletion = onCompletion
        coordinator.placeholder = placeholder
        view.contentMode = contentMode
        view.sizingMode = sizingMode
        if !coordinator.didSetupView {
            coordinator.didSetupView = true
            onSetup?(view)
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
        coordinator.loadPlaceholder(for: url, into: view)
        view.loadImage(
            url: url,
            levelOfIntegrity: levelOfIntegrity,
            prefetchCount: prefetchCount
        ) { [weak coordinator] result in
            coordinator?.imageDidComplete(result)
        }
    }

    @MainActor
    public final class Coordinator {
        fileprivate var url: URL?
        fileprivate var levelOfIntegrity: Double?
        fileprivate var prefetchCount: Int?
        fileprivate var onCompletion: (@MainActor @Sendable (Result<CGImage, any Error>) -> Void)?
        fileprivate var placeholder: (@MainActor @Sendable () async throws -> CGImage)?
        fileprivate var didSetupView = false
        private var placeholderTask: Task<Void, Never>?
        private var placeholderURL: URL?
        private var didLoadImageSuccessfully = false

        fileprivate func loadPlaceholder(for url: URL, into view: Vulp_UIKit.AsyncImageView) {
            placeholderTask?.cancel()
            placeholderURL = url
            didLoadImageSuccessfully = false
            view.showPlaceholder(nil)
            guard let placeholder else { return }

            placeholderTask = Task { @MainActor [weak self, weak view] in
                do {
                    let image = try await placeholder()
                    try Task.checkCancellation()
                    guard let self,
                          let view,
                          self.placeholderURL == url,
                          !self.didLoadImageSuccessfully
                    else {
                        return
                    }
                    view.showPlaceholder(image)
                } catch is CancellationError {
                    return
                } catch {
                    // A failed placeholder should not prevent the source image from loading.
                }
            }
        }

        fileprivate func imageDidComplete(_ result: Result<CGImage, any Error>) {
            if case .success = result {
                didLoadImageSuccessfully = true
            }
            onCompletion?(result)
        }
    }
}
#endif
