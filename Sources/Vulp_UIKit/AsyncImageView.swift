#if canImport(UIKit)
import UIKit
@_exported import Vulp

/// A container view that owns and lays out its image view.
@MainActor
public final class AsyncImageView: UIView {
    private let imageView = UIImageView()
    private let sequencePlayback = ImageSequencePlayback()
    private var makeImageOperation: (@MainActor @Sendable (CGSize?, CGFloat) -> ImageLoadingOperation?)?
    private var restartImageLoadOnAttach: (@MainActor @Sendable () -> Void)?
    private var currentCacheIdentifier: String?
    private var loadedCacheIdentifier: String?
    private var loadedStaticSequenceIdentifier: String?
    private var imageLoadTask: Task<Void, Never>?
    private var imageFailureHandler: (@MainActor @Sendable (any Error) -> Void)?

    /// Controls request-builder loads; sequence loads use their explicit `targetSize` argument.
    public var sizingMode: ImageViewSizingMode = .viewBounds {
        didSet {
            currentCacheIdentifier = nil
            setNeedsLayout()
            updateImageIfNeeded()
        }
    }

    public var image: UIImage? {
        get { imageView.image }
        set {
            imageLoadTask?.cancel()
            imageLoadTask = nil
            makeImageOperation = nil
            restartImageLoadOnAttach = nil
            currentCacheIdentifier = nil
            loadedCacheIdentifier = nil
            loadedStaticSequenceIdentifier = nil
            sequencePlayback.stop()
            imageView.image = newValue
        }
    }

    public override var contentMode: UIView.ContentMode {
        didSet { imageView.contentMode = contentMode }
    }

    /// Loads and plays an image source from a URL at this view's current pixel size.
    public func loadImage(
        url: URL,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3,
        onFailure: (@MainActor @Sendable (any Error) -> Void)? = nil
    ) {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        makeImageOperation = nil
        currentCacheIdentifier = nil
        loadedCacheIdentifier = nil
        loadedStaticSequenceIdentifier = nil
        let asset = RemoteMediaAsset(url: url)
        restartImageLoadOnAttach = { [weak self] in
            self?.startImageLoad(
                asset: asset,
                levelOfIntegrity: levelOfIntegrity,
                prefetchCount: prefetchCount,
                onFailure: onFailure
            )
        }
        sequencePlayback.stop()
        imageFailureHandler = onFailure
        imageView.image = nil
        if window != nil {
            startImageLoad(
                asset: asset,
                levelOfIntegrity: levelOfIntegrity,
                prefetchCount: prefetchCount,
                onFailure: onFailure
            )
        }
    }

    /// Loads an image source and plays it when it contains multiple frames.
    public func loadImage(
        asset: any MediaAsset,
        targetSize: CGSize,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3
    ) async throws {
        try await loadImage(
            asset: asset,
            using: MediaImageLoader.default,
            targetSize: targetSize,
            levelOfIntegrity: levelOfIntegrity,
            prefetchCount: prefetchCount
        )
    }

    /// Loads an image source and plays it when it contains multiple frames.
    public func loadImage<Loader: MediaImageSequenceLoading>(
        asset: any MediaAsset,
        using loader: Loader,
        targetSize: CGSize,
        levelOfIntegrity: Double = 1,
        prefetchCount: Int = 3
    ) async throws {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        makeImageOperation = nil
        restartImageLoadOnAttach = nil
        currentCacheIdentifier = nil
        loadedCacheIdentifier = nil
        loadedStaticSequenceIdentifier = nil
        let sequence = try await loader.loadSequence(from: asset)
        let playbackPlan = await sequence.playbackPlan(levelOfIntegrity: levelOfIntegrity)
        let frameLoader = ImageSequenceFrameLoader(
            sequence: sequence,
            using: loader,
            targetSize: targetSize,
            prefetchCount: prefetchCount,
            playbackFrameIndices: playbackPlan.frameIndices
        )
        guard let firstIndex = playbackPlan.frameIndices.first else { return }
        let firstFrame = try await frameLoader.frame(at: firstIndex)
        try Task.checkCancellation()
        sequencePlayback.play(
            firstFrame: firstFrame,
            frameLoader: frameLoader,
            frameIndices: playbackPlan.frameIndices,
            in: imageView,
            frameInterval: playbackPlan.frameRate.frameDuration
        )
    }

    /// Loads a request at this view's point bounds and display scale, updating when its cache tier changes.
    public func loadImage<Request: MediaImageRequestProtocol>(
        request: @escaping @MainActor @Sendable (CGSize?) throws -> Request,
        onFailure: (@MainActor @Sendable (any Error) -> Void)? = nil
    ) {
        loadImage(
            using: MediaImageLoader.default,
            request: { targetSize, _ in try request(targetSize) },
            onFailure: onFailure
        )
    }

    /// Loads a request at this view's point bounds and display scale, updating when its cache tier changes.
    public func loadImage<Request: MediaImageRequestProtocol, Loader: MediaImageLoading>(
        using loader: Loader,
        request: @escaping @MainActor @Sendable (CGSize?, CGFloat) throws -> Request,
        onFailure: (@MainActor @Sendable (any Error) -> Void)? = nil
    ) {
        imageLoadTask?.cancel()
        restartImageLoadOnAttach = nil
        sequencePlayback.stop()
        currentCacheIdentifier = nil
        loadedStaticSequenceIdentifier = nil
        imageFailureHandler = onFailure
        makeImageOperation = { targetSize, scale in
            do {
                let imageRequest = try request(targetSize, scale)
                return ImageLoadingOperation(
                    cacheIdentifier: imageRequest.cacheIdentifier,
                    load: { try await loader.load(imageRequest) }
                )
            } catch {
                return nil
            }
        }
        updateImageIfNeeded()
    }

    /// Stops sequence playback while keeping the currently displayed frame.
    public func stopAnimatingSequence() {
        sequencePlayback.stop()
    }

    isolated deinit {
        imageLoadTask?.cancel()
        sequencePlayback.stop()
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(imageView)
        imageView.isAccessibilityElement = false
        contentMode = .scaleAspectFit
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        addSubview(imageView)
        imageView.isAccessibilityElement = false
        contentMode = .scaleAspectFit
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        updateImageIfNeeded()
    }

    public override func willMove(toSuperview newSuperview: UIView?) {
        if newSuperview == nil, superview != nil {
            cancelImageLoadForDetachment()
        }
        super.willMove(toSuperview: newSuperview)
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard superview != nil, window != nil else { return }
        restartImageLoadIfNeeded()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            cancelImageLoadForDetachment()
            return
        }

        restartImageLoadIfNeeded()
    }

    private func restartImageLoadIfNeeded() {
        if let restartImageLoadOnAttach {
            restartImageLoadOnAttach()
        } else {
            updateImageIfNeeded()
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.displayScale != traitCollection.displayScale else { return }
        currentCacheIdentifier = nil
        updateImageIfNeeded()
    }

    private func updateImageIfNeeded() {
        guard window != nil, let makeImageOperation else { return }
        let targetSize: CGSize?
        let scale: CGFloat
        if sizingMode == .viewBounds {
            guard bounds.width > 0, bounds.height > 0 else { return }
            targetSize = CGSize(width: bounds.width.rounded(.up), height: bounds.height.rounded(.up))
            scale = traitCollection.displayScale
        } else {
            targetSize = nil
            scale = 1
        }

        guard let operation = makeImageOperation(targetSize, scale),
              operation.cacheIdentifier != currentCacheIdentifier else { return }

        currentCacheIdentifier = operation.cacheIdentifier
        imageLoadTask?.cancel()
        imageLoadTask = nil
        if loadedCacheIdentifier == operation.cacheIdentifier, imageView.image != nil {
            return
        }
        imageView.image = nil
        imageLoadTask = Task { @MainActor [weak self] in
            do {
                let image = try await operation.load()
                try Task.checkCancellation()
                guard let self,
                      self.currentCacheIdentifier == operation.cacheIdentifier
                else {
                    return
                }
                self.loadedCacheIdentifier = operation.cacheIdentifier
                self.imageView.image = image
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.currentCacheIdentifier == operation.cacheIdentifier
                else {
                    return
                }
                self.imageFailureHandler?(error)
            }
        }
    }

    private func startImageLoad(
        asset: any MediaAsset,
        levelOfIntegrity: Double,
        prefetchCount: Int,
        onFailure: (@MainActor @Sendable (any Error) -> Void)?
    ) {
        guard window != nil, imageLoadTask == nil else { return }
        imageLoadTask?.cancel()
        sequencePlayback.stop()

        let scale = traitCollection.displayScale
        let targetSize = CGSize(
            width: (bounds.width * scale).rounded(.up),
            height: (bounds.height * scale).rounded(.up)
        )
        let sequenceIdentifier = "\(asset.uniqueKey)|\(targetSize.width)x\(targetSize.height)|integrity:\(levelOfIntegrity)"
        guard loadedStaticSequenceIdentifier != sequenceIdentifier || imageView.image == nil else { return }
        let loader = MediaImageLoader.default
        imageLoadTask = Task { @MainActor [weak self] in
            do {
                let sequence = try await loader.loadSequence(from: asset)
                let playbackPlan = await sequence.playbackPlan(levelOfIntegrity: levelOfIntegrity)
                let frameLoader = ImageSequenceFrameLoader(
                    sequence: sequence,
                    using: loader,
                    targetSize: targetSize,
                    prefetchCount: prefetchCount,
                    playbackFrameIndices: playbackPlan.frameIndices
                )
                guard let firstIndex = playbackPlan.frameIndices.first else { return }
                let firstFrame: UIImage
                do {
                    firstFrame = try await frameLoader.frame(at: firstIndex)
                } catch {
                    await frameLoader.cancel()
                    throw error
                }
                try Task.checkCancellation()
                guard let self else {
                    await frameLoader.cancel()
                    return
                }
                self.loadedStaticSequenceIdentifier = !playbackPlan.isAnimated
                    ? sequenceIdentifier
                    : nil
                self.sequencePlayback.play(
                    firstFrame: firstFrame,
                    frameLoader: frameLoader,
                    frameIndices: playbackPlan.frameIndices,
                    isAnimated: playbackPlan.isAnimated,
                    in: self.imageView,
                    frameInterval: playbackPlan.frameRate.frameDuration
                )
            } catch is CancellationError {
                return
            } catch {
                onFailure?(error)
            }
        }
    }

    private func cancelImageLoadForDetachment() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        currentCacheIdentifier = nil
        sequencePlayback.stop()
    }
}

private struct ImageLoadingOperation {
    let cacheIdentifier: String
    let load: @MainActor @Sendable () async throws -> UIImage
}

@MainActor
private final class ImageSequencePlayback {
    private weak var imageView: UIImageView?
    private var updateLink: UIUpdateLink?
    private var frameLoadingTask: Task<Void, Never>?
    private var loadFrame: (@MainActor @Sendable (Int) async throws -> UIImage)?
    private var cancelFrameLoading: (@Sendable () async -> Void)?
    private var frameIndices: [Int] = []
    private var frameInterval: TimeInterval = ImageSequenceFrameRate.fps10.frameDuration
    private var startTimestamp: CFTimeInterval?
    private var displayedPosition = 0
    private var desiredPosition = 0

    func play<Loader: MediaImageLoading>(
        firstFrame: UIImage,
        frameLoader: ImageSequenceFrameLoader<Loader>,
        frameIndices: [Int],
        isAnimated: Bool,
        in imageView: UIImageView,
        frameInterval: TimeInterval
    ) {
        stop()
        self.imageView = imageView
        self.frameInterval = frameInterval
        self.frameIndices = frameIndices
        self.displayedPosition = 0
        self.desiredPosition = 0
        self.loadFrame = { index in try await frameLoader.frame(at: index) }
        self.cancelFrameLoading = { await frameLoader.cancel() }
        imageView.image = firstFrame

        guard isAnimated else {
            let cancelFrameLoading = self.cancelFrameLoading
            self.cancelFrameLoading = nil
            loadFrame = nil
            self.frameIndices = []
            if let cancelFrameLoading {
                Task { await cancelFrameLoading() }
            }
            return
        }

        let updateLink = UIUpdateLink(view: imageView) { [weak self] _, updateInfo in
            self?.updateLinkDidFire(updateInfo)
        }
        updateLink.requiresContinuousUpdates = true
        updateLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 1,
            maximum: Float(1 / frameInterval),
            preferred: Float(1 / frameInterval)
        )
        updateLink.isEnabled = true
        self.updateLink = updateLink
    }

    func stop() {
        updateLink?.isEnabled = false
        updateLink = nil
        frameLoadingTask?.cancel()
        frameLoadingTask = nil
        let cancelFrameLoading = self.cancelFrameLoading
        self.cancelFrameLoading = nil
        loadFrame = nil
        frameIndices = []
        startTimestamp = nil
        imageView = nil
        if let cancelFrameLoading {
            Task { await cancelFrameLoading() }
        }
    }

    private func updateLinkDidFire(_ updateInfo: UIUpdateInfo) {
        guard !frameIndices.isEmpty else { return }
        guard let startTimestamp else {
            self.startTimestamp = updateInfo.modelTime
            return
        }

        let elapsed = max(0, updateInfo.modelTime - startTimestamp)
        let position = Int(elapsed / frameInterval) % frameIndices.count
        desiredPosition = position
        guard position != displayedPosition,
              frameLoadingTask == nil,
              let loadFrame
        else {
            return
        }

        let index = frameIndices[position]
        frameLoadingTask = Task { @MainActor [weak self] in
            defer { self?.frameLoadingTask = nil }
            do {
                let image = try await loadFrame(index)
                try Task.checkCancellation()
                guard let self, self.desiredPosition == position else { return }
                self.imageView?.image = image
                self.displayedPosition = position
            } catch is CancellationError {
                return
            } catch {
                self?.stop()
            }
        }
    }
}
#endif
